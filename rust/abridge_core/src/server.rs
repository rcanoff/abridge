use std::sync::{Arc, Condvar, Mutex};

use axum::Router;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

use crate::{
  config::{ServerConfig, validate_config},
  diagnostics::{ProviderStatus, ServerStatus},
  error::CoreError,
  http,
  mcp::McpState,
  providers::ProviderBridge,
  usage_audit::{
    EVENT_API_KEY_ROTATION, EVENT_PORT_BIND, EVENT_SERVER_START, EVENT_SERVER_STOP, UsageAuditEntry, UsageAuditStore,
  },
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ServerPhase {
  Stopped,
  Starting,
  Running,
  Stopping,
}

#[derive(uniffi::Object)]
pub struct ServerHandle {
  inner: Arc<Mutex<ServerInner>>,
  lifecycle: Arc<Condvar>,
}

struct ServerInner {
  config: ServerConfig,
  #[allow(dead_code)]
  provider: Arc<dyn ProviderBridge>,
  audit_store: Arc<UsageAuditStore>,
  status: ServerStatus,
  phase: ServerPhase,
  start_generation: u64,
  start_in_progress: bool,
  runtime: Option<tokio::runtime::Runtime>,
  shutdown_tx: Option<oneshot::Sender<()>>,
  server_task: Option<JoinHandle<()>>,
}

struct ShutdownParts {
  runtime: Option<tokio::runtime::Runtime>,
  shutdown_tx: Option<oneshot::Sender<()>>,
  server_task: Option<JoinHandle<()>>,
}

struct StartInProgressGuard {
  inner: Arc<Mutex<ServerInner>>,
  lifecycle: Arc<Condvar>,
}

impl Drop for StartInProgressGuard {
  fn drop(&mut self) {
    if let Ok(mut guard) = self.inner.lock() {
      guard.start_in_progress = false;
    }
    self.lifecycle.notify_all();
  }
}

fn bind_address(host: &str, port: u16) -> String {
  if host.contains(':') {
    format!("[{host}]:{port}")
  } else {
    format!("{host}:{port}")
  }
}

fn initial_status(config: &ServerConfig) -> ServerStatus {
  ServerStatus {
    running: false,
    bound_host: config.host.clone(),
    bound_port: config.port,
    provider_statuses: config
      .enabled_providers
      .iter()
      .map(|p| ProviderStatus {
        name: p.name.clone(),
        enabled: p.enabled,
        healthy: false,
      })
      .collect(),
    last_error: None,
  }
}

fn running_status(config: &ServerConfig) -> ServerStatus {
  ServerStatus {
    running: true,
    bound_host: config.host.clone(),
    bound_port: config.port,
    provider_statuses: config
      .enabled_providers
      .iter()
      .map(|p| ProviderStatus {
        name: p.name.clone(),
        enabled: p.enabled,
        healthy: p.enabled,
      })
      .collect(),
    last_error: None,
  }
}

fn stopped_status_with_error(config: &ServerConfig, message: String) -> ServerStatus {
  ServerStatus {
    running: false,
    bound_host: config.host.clone(),
    bound_port: config.port,
    provider_statuses: config
      .enabled_providers
      .iter()
      .map(|p| ProviderStatus {
        name: p.name.clone(),
        enabled: p.enabled,
        healthy: false,
      })
      .collect(),
    last_error: Some(message),
  }
}

fn build_runtime() -> Result<tokio::runtime::Runtime, CoreError> {
  tokio::runtime::Builder::new_multi_thread()
    .enable_all()
    .build()
    .map_err(|error| CoreError::RuntimeFailed {
      message: error.to_string(),
    })
}

fn clear_stale_runtime(inner: &mut ServerInner) {
  if inner.server_task.is_none() {
    inner.runtime.take();
    inner.shutdown_tx.take();
  }
}

fn take_shutdown_parts(inner: &mut ServerInner) -> ShutdownParts {
  ShutdownParts {
    runtime: inner.runtime.take(),
    shutdown_tx: inner.shutdown_tx.take(),
    server_task: inner.server_task.take(),
  }
}

fn run_shutdown(parts: ShutdownParts) {
  match parts {
    ShutdownParts {
      runtime: Some(runtime),
      shutdown_tx: Some(shutdown_tx),
      server_task: Some(server_task),
    } => {
      let join = std::thread::spawn(move || {
        runtime.block_on(async {
          if shutdown_tx.send(()).is_err() {
            tracing::warn!("shutdown signal channel closed before send");
          }
          if server_task.await.is_err() {
            tracing::warn!("http server task join failed during shutdown");
          }
        });
      });
      if join.join().is_err() {
        tracing::error!("shutdown helper thread panicked");
      }
    }
    ShutdownParts {
      runtime: Some(runtime), ..
    } => drop(runtime),
    ShutdownParts { .. } => {}
  }
}

async fn start_http_server(
  addr: &str,
  router: Router,
  inner: Arc<Mutex<ServerInner>>,
  audit_store: Arc<UsageAuditStore>,
) -> Result<(oneshot::Sender<()>, JoinHandle<()>), CoreError> {
  let listener = tokio::net::TcpListener::bind(addr)
    .await
    .map_err(|error| CoreError::BindFailed {
      message: error.to_string(),
    })?;
  audit_store.record(EVENT_PORT_BIND, None, true, None);
  let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
  let task_inner = inner.clone();
  let task = tokio::spawn(async move {
    let result = axum::serve(listener, router)
      .with_graceful_shutdown(async {
        let _ = shutdown_rx.await;
      })
      .await;

    if let Err(error) = result {
      tracing::error!(%error, "http server exited with error");
      if let Ok(mut guard) = task_inner.lock() {
        if matches!(guard.phase, ServerPhase::Running | ServerPhase::Starting) {
          guard.phase = ServerPhase::Stopped;
          guard.status = stopped_status_with_error(&guard.config, error.to_string());
          guard.shutdown_tx = None;
          guard.server_task = None;
        }
      }
    }
  });

  Ok((shutdown_tx, task))
}

fn abort_started_server(
  runtime: tokio::runtime::Runtime,
  shutdown_tx: oneshot::Sender<()>,
  server_task: JoinHandle<()>,
) {
  run_shutdown(ShutdownParts {
    runtime: Some(runtime),
    shutdown_tx: Some(shutdown_tx),
    server_task: Some(server_task),
  });
}

fn wait_for_start_completion(inner: &Arc<Mutex<ServerInner>>, lifecycle: &Arc<Condvar>) -> Result<(), CoreError> {
  let mut guard = inner.lock().map_err(|_| CoreError::StateUnavailable)?;
  while guard.start_in_progress {
    guard = lifecycle.wait(guard).map_err(|_| CoreError::StateUnavailable)?;
  }
  Ok(())
}

pub fn create_server(config: ServerConfig, provider: Box<dyn ProviderBridge>) -> Result<Arc<ServerHandle>, CoreError> {
  validate_config(&config)?;

  let audit_store = Arc::new(UsageAuditStore::new());

  Ok(Arc::new(ServerHandle {
    inner: Arc::new(Mutex::new(ServerInner {
      status: initial_status(&config),
      config,
      provider: Arc::from(provider),
      audit_store: audit_store.clone(),
      phase: ServerPhase::Stopped,
      start_generation: 0,
      start_in_progress: false,
      runtime: None,
      shutdown_tx: None,
      server_task: None,
    })),
    lifecycle: Arc::new(Condvar::new()),
  }))
}

impl Drop for ServerHandle {
  fn drop(&mut self) {
    let (parts, last_error) = match self.inner.lock() {
      Ok(mut inner) => {
        let last_error = inner.status.last_error.clone();
        inner.phase = ServerPhase::Stopped;
        (take_shutdown_parts(&mut inner), last_error)
      }
      Err(_) => return,
    };
    run_shutdown(parts);

    if let Ok(mut inner) = self.inner.lock() {
      inner.status = initial_status(&inner.config);
      inner.status.last_error = last_error;
    }
  }
}

#[uniffi::export]
impl ServerHandle {
  pub fn start(&self) -> Result<(), CoreError> {
    let (addr, generation) = {
      let mut inner = self.inner.lock().map_err(|_| CoreError::StateUnavailable)?;
      if inner.phase == ServerPhase::Running || inner.phase == ServerPhase::Starting {
        return Err(CoreError::AlreadyRunning);
      }
      if inner.phase == ServerPhase::Stopping {
        return Err(CoreError::StateUnavailable);
      }
      clear_stale_runtime(&mut inner);
      inner.phase = ServerPhase::Starting;
      inner.start_generation += 1;
      inner.start_in_progress = true;
      let generation = inner.start_generation;
      (bind_address(&inner.config.host, inner.config.port), generation)
    };

    let _start_guard = StartInProgressGuard {
      inner: self.inner.clone(),
      lifecycle: self.lifecycle.clone(),
    };

    #[cfg(any(test, feature = "test-sync"))]
    start_test_sync::maybe_pause_for_test();

    let runtime = match build_runtime() {
      Ok(runtime) => runtime,
      Err(error) => {
        let mut inner = self.inner.lock().map_err(|_| CoreError::StateUnavailable)?;
        if inner.phase == ServerPhase::Starting && inner.start_generation == generation {
          inner.phase = ServerPhase::Stopped;
          inner.status = stopped_status_with_error(&inner.config, error.to_string());
        }
        return Err(error);
      }
    };

    let (mcp_state, audit_store) = {
      let inner = self.inner.lock().map_err(|_| CoreError::StateUnavailable)?;
      let audit_store = inner.audit_store.clone();
      let mcp_state = McpState {
        bearer_token: inner.config.bearer_token.clone(),
        app_version: inner.config.app_version.clone(),
        enabled_capabilities: inner.config.enabled_capabilities.clone(),
        enabled_providers: inner.config.enabled_providers.clone(),
        provider: inner.provider.clone(),
        audit_store: audit_store.clone(),
      };
      (mcp_state, audit_store)
    };
    let router = http::router(mcp_state);
    let started = runtime.block_on(start_http_server(&addr, router, self.inner.clone(), audit_store));

    let (shutdown_tx, server_task) = match started {
      Ok(parts) => parts,
      Err(error) => {
        let mut inner = self.inner.lock().map_err(|_| CoreError::StateUnavailable)?;
        if inner.phase == ServerPhase::Starting && inner.start_generation == generation {
          inner.phase = ServerPhase::Stopped;
          inner.status = stopped_status_with_error(&inner.config, error.to_string());
        }
        return Err(error);
      }
    };

    let mut inner = self.inner.lock().map_err(|_| CoreError::StateUnavailable)?;
    if inner.phase == ServerPhase::Starting && inner.start_generation == generation {
      inner.runtime = Some(runtime);
      inner.shutdown_tx = Some(shutdown_tx);
      inner.server_task = Some(server_task);
      inner.phase = ServerPhase::Running;
      inner.status = running_status(&inner.config);
      inner.audit_store.record(EVENT_SERVER_START, None, true, None);
      return Ok(());
    }

    drop(inner);
    abort_started_server(runtime, shutdown_tx, server_task);

    let mut inner = self.inner.lock().map_err(|_| CoreError::StateUnavailable)?;
    if inner.start_generation == generation {
      inner.phase = ServerPhase::Stopped;
      inner.status = initial_status(&inner.config);
    }
    Err(CoreError::StartCancelled)
  }

  pub fn stop(&self) -> Result<(), CoreError> {
    let (wait_for_start, record_server_stop) = {
      let mut inner = self.inner.lock().map_err(|_| CoreError::StateUnavailable)?;
      match inner.phase {
        ServerPhase::Stopped => {
          clear_stale_runtime(&mut inner);
          return Ok(());
        }
        ServerPhase::Starting => {
          inner.start_generation += 1;
          (inner.start_in_progress, false)
        }
        ServerPhase::Stopping => return Ok(()),
        ServerPhase::Running => {
          inner.phase = ServerPhase::Stopping;
          (false, true)
        }
      }
    };

    if wait_for_start {
      wait_for_start_completion(&self.inner, &self.lifecycle)?;
      let mut inner = self.inner.lock().map_err(|_| CoreError::StateUnavailable)?;
      inner.phase = ServerPhase::Stopped;
      inner.status = initial_status(&inner.config);
      return Ok(());
    }

    let parts = {
      let mut inner = self.inner.lock().map_err(|_| CoreError::StateUnavailable)?;
      if inner.phase == ServerPhase::Running || inner.phase == ServerPhase::Stopping {
        take_shutdown_parts(&mut inner)
      } else {
        ShutdownParts {
          runtime: None,
          shutdown_tx: None,
          server_task: None,
        }
      }
    };
    run_shutdown(parts);

    let mut inner = self.inner.lock().map_err(|_| CoreError::StateUnavailable)?;
    if record_server_stop {
      inner.audit_store.record(EVENT_SERVER_STOP, None, true, None);
    }
    inner.phase = ServerPhase::Stopped;
    inner.status = initial_status(&inner.config);
    Ok(())
  }

  pub fn usage_audit_entries(&self) -> Vec<UsageAuditEntry> {
    match self.inner.lock() {
      Ok(inner) => inner.audit_store.entries(),
      Err(_) => Vec::new(),
    }
  }

  pub fn set_usage_logging_enabled(&self, enabled: bool) {
    if let Ok(inner) = self.inner.lock() {
      inner.audit_store.set_logging_enabled(enabled);
    }
  }

  pub fn usage_logging_enabled(&self) -> bool {
    match self.inner.lock() {
      Ok(inner) => inner.audit_store.logging_enabled(),
      Err(_) => false,
    }
  }

  pub fn record_api_key_rotation(&self) {
    if let Ok(inner) = self.inner.lock() {
      inner.audit_store.record(EVENT_API_KEY_ROTATION, None, true, None);
    }
  }

  pub fn status(&self) -> ServerStatus {
    match self.inner.lock() {
      Ok(inner) => inner.status.clone(),
      Err(_) => ServerStatus {
        running: false,
        bound_host: String::new(),
        bound_port: 0,
        provider_statuses: Vec::new(),
        last_error: Some("server state unavailable".into()),
      },
    }
  }
}

#[cfg(any(test, feature = "test-sync"))]
pub mod start_test_sync {
  use std::sync::{Condvar, Mutex};

  #[derive(Debug, Default)]
  struct SyncState {
    armed: bool,
    paused: bool,
    continue_requested: bool,
  }

  static STATE: Mutex<SyncState> = Mutex::new(SyncState {
    armed: false,
    paused: false,
    continue_requested: false,
  });
  static CV: Condvar = Condvar::new();

  fn with_state<F, R>(f: F) -> R
  where
    F: FnOnce(&mut SyncState) -> R,
  {
    let mut guard = STATE.lock().expect("start_test_sync state lock");
    f(&mut guard)
  }

  fn wait_while<F>(
    mut guard: std::sync::MutexGuard<'_, SyncState>,
    predicate: F,
  ) -> std::sync::MutexGuard<'_, SyncState>
  where
    F: Fn(&SyncState) -> bool,
  {
    while predicate(&guard) {
      guard = CV.wait(guard).expect("start_test_sync condvar wait");
    }
    guard
  }

  /// Arms the next `start()` to block after entering `Starting` + `start_in_progress`.
  pub fn arm_pause_before_bind() {
    with_state(|state| {
      state.armed = true;
      state.paused = false;
      state.continue_requested = false;
    });
  }

  /// Blocks until a paused `start()` reaches the bind pause point.
  pub fn wait_until_paused() {
    let _guard = wait_while(STATE.lock().expect("start_test_sync state lock"), |state| !state.paused);
  }

  /// Releases a paused `start()` so it can proceed with runtime creation and bind.
  pub fn continue_paused_start() {
    with_state(|state| {
      state.continue_requested = true;
    });
    CV.notify_all();
  }

  /// Resets sync state and unblocks any paused `start()` for test isolation.
  pub fn disarm() {
    with_state(|state| {
      state.armed = false;
      state.paused = false;
      state.continue_requested = true;
    });
    CV.notify_all();
  }

  pub(super) fn maybe_pause_for_test() {
    let mut guard = STATE.lock().expect("start_test_sync state lock");
    if !guard.armed {
      return;
    }

    guard.paused = true;
    CV.notify_all();
    guard = wait_while(guard, |state| !state.continue_requested);
    guard.armed = false;
    guard.paused = false;
    guard.continue_requested = false;
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::config::{ProviderConfig, ProviderRequest, ProviderResponse, ServerConfig};

  struct StubProvider;

  impl ProviderBridge for StubProvider {
    fn call_provider(&self, _request: ProviderRequest) -> ProviderResponse {
      ProviderResponse {
        ok: true,
        payload_json: "{}".into(),
        error_json: None,
      }
    }
  }

  fn test_config() -> ServerConfig {
    ServerConfig {
      host: "127.0.0.1".into(),
      port: 18_080,
      bearer_token: "test-token".into(),
      app_version: "test".into(),
      enabled_providers: vec![ProviderConfig {
        name: "eventkit".into(),
        enabled: true,
      }],
      enabled_capabilities: vec![],
    }
  }

  fn inject_stale_runtime_after_serve_failure(handle: &ServerHandle) {
    let mut inner = handle.inner.lock().expect("lock inner");
    inner.phase = ServerPhase::Stopped;
    inner.status = stopped_status_with_error(&inner.config, "simulated serve failure".into());
    inner.shutdown_tx = None;
    inner.server_task = None;
    inner.runtime = Some(build_runtime().expect("build runtime"));
  }

  #[test]
  fn stop_clears_stale_runtime_when_already_stopped() {
    let handle = create_server(test_config(), Box::new(StubProvider)).expect("create_server");
    inject_stale_runtime_after_serve_failure(&handle);

    handle.stop().expect("stop on stale stopped server");

    let inner = handle.inner.lock().expect("lock inner");
    assert!(inner.runtime.is_none());
    assert_eq!(inner.phase, ServerPhase::Stopped);
  }
}

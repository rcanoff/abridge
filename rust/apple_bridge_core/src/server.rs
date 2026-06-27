use std::sync::{Arc, Mutex};

use axum::Router;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

use crate::{
  config::{validate_config, ServerConfig},
  diagnostics::{ProviderStatus, ServerStatus},
  error::CoreError,
  http,
  providers::ProviderBridge,
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
}

struct ServerInner {
  config: ServerConfig,
  #[allow(dead_code)]
  provider: Arc<dyn ProviderBridge>,
  status: ServerStatus,
  phase: ServerPhase,
  start_generation: u64,
  runtime: Option<tokio::runtime::Runtime>,
  shutdown_tx: Option<oneshot::Sender<()>>,
  server_task: Option<JoinHandle<()>>,
}

struct ShutdownParts {
  runtime: Option<tokio::runtime::Runtime>,
  shutdown_tx: Option<oneshot::Sender<()>>,
  server_task: Option<JoinHandle<()>>,
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
          let _ = shutdown_tx.send(());
          let _ = server_task.await;
        });
      });
      let _ = join.join();
    }
    ShutdownParts {
      runtime: Some(runtime),
      ..
    } => drop(runtime),
    ShutdownParts { .. } => {}
  }
}

async fn start_http_server(
  addr: &str,
  router: Router,
  inner: Arc<Mutex<ServerInner>>,
) -> Result<(oneshot::Sender<()>, JoinHandle<()>), CoreError> {
  let listener = tokio::net::TcpListener::bind(addr).await.map_err(|error| CoreError::BindFailed {
    message: error.to_string(),
  })?;
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

fn abort_started_server(runtime: tokio::runtime::Runtime, shutdown_tx: oneshot::Sender<()>, server_task: JoinHandle<()>) {
  run_shutdown(ShutdownParts {
    runtime: Some(runtime),
    shutdown_tx: Some(shutdown_tx),
    server_task: Some(server_task),
  });
}

pub fn create_server(
  config: ServerConfig,
  provider: Box<dyn ProviderBridge>,
) -> Result<Arc<ServerHandle>, CoreError> {
  validate_config(&config)?;

  Ok(Arc::new(ServerHandle {
    inner: Arc::new(Mutex::new(ServerInner {
      status: initial_status(&config),
      config,
      provider: Arc::from(provider),
      phase: ServerPhase::Stopped,
      start_generation: 0,
      runtime: None,
      shutdown_tx: None,
      server_task: None,
    })),
  }))
}

impl Drop for ServerHandle {
  fn drop(&mut self) {
    let parts = match self.inner.lock() {
      Ok(mut inner) => {
        inner.phase = ServerPhase::Stopped;
        take_shutdown_parts(&mut inner)
      }
      Err(_) => return,
    };
    run_shutdown(parts);

    if let Ok(mut inner) = self.inner.lock() {
      inner.status = initial_status(&inner.config);
    }
  }
}

#[uniffi::export]
impl ServerHandle {
  pub fn start(&self) -> Result<(), CoreError> {
    let (addr, generation) = {
      let mut inner = self
        .inner
        .lock()
        .map_err(|_| CoreError::StateUnavailable)?;
      if inner.phase == ServerPhase::Running || inner.phase == ServerPhase::Starting {
        return Err(CoreError::AlreadyRunning);
      }
      if inner.phase == ServerPhase::Stopping {
        return Err(CoreError::StateUnavailable);
      }
      clear_stale_runtime(&mut inner);
      inner.phase = ServerPhase::Starting;
      inner.start_generation += 1;
      let generation = inner.start_generation;
      (bind_address(&inner.config.host, inner.config.port), generation)
    };

    let runtime = build_runtime()?;
    let router = http::router();
    let started = runtime.block_on(start_http_server(&addr, router, self.inner.clone()));

    let (shutdown_tx, server_task) = match started {
      Ok(parts) => parts,
      Err(error) => {
        let mut inner = self
          .inner
          .lock()
          .map_err(|_| CoreError::StateUnavailable)?;
        if inner.phase == ServerPhase::Starting && inner.start_generation == generation {
          inner.phase = ServerPhase::Stopped;
          inner.status = stopped_status_with_error(&inner.config, error.to_string());
        }
        return Err(error);
      }
    };

    let mut inner = self
      .inner
      .lock()
      .map_err(|_| CoreError::StateUnavailable)?;
    if inner.phase == ServerPhase::Starting && inner.start_generation == generation {
      inner.runtime = Some(runtime);
      inner.shutdown_tx = Some(shutdown_tx);
      inner.server_task = Some(server_task);
      inner.phase = ServerPhase::Running;
      inner.status = running_status(&inner.config);
      return Ok(());
    }

    drop(inner);
    abort_started_server(runtime, shutdown_tx, server_task);

    let mut inner = self
      .inner
      .lock()
      .map_err(|_| CoreError::StateUnavailable)?;
    inner.phase = ServerPhase::Stopped;
    inner.status = initial_status(&inner.config);
    Err(CoreError::StartCancelled)
  }

  pub fn stop(&self) -> Result<(), CoreError> {
    let parts = {
      let mut inner = self
        .inner
        .lock()
        .map_err(|_| CoreError::StateUnavailable)?;
      match inner.phase {
        ServerPhase::Stopped => return Ok(()),
        ServerPhase::Starting => {
          inner.start_generation += 1;
          inner.phase = ServerPhase::Stopped;
          inner.status = initial_status(&inner.config);
          return Ok(());
        }
        ServerPhase::Stopping => return Ok(()),
        ServerPhase::Running => {
          inner.phase = ServerPhase::Stopping;
          take_shutdown_parts(&mut inner)
        }
      }
    };
    run_shutdown(parts);

    let mut inner = self
      .inner
      .lock()
      .map_err(|_| CoreError::StateUnavailable)?;
    inner.phase = ServerPhase::Stopped;
    inner.status = initial_status(&inner.config);
    Ok(())
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
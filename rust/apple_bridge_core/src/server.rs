use std::sync::{Arc, Mutex};

use crate::{
  config::{validate_config, ServerConfig},
  diagnostics::{ProviderStatus, ServerStatus},
  error::CoreError,
  providers::ProviderBridge,
};

#[derive(uniffi::Object)]
pub struct ServerHandle {
  inner: Mutex<ServerInner>,
}

struct ServerInner {
  config: ServerConfig,
  #[allow(dead_code)]
  provider: Arc<dyn ProviderBridge>,
  status: ServerStatus,
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

pub fn create_server(
  config: ServerConfig,
  provider: Box<dyn ProviderBridge>,
) -> Result<Arc<ServerHandle>, CoreError> {
  validate_config(&config)?;

  Ok(Arc::new(ServerHandle {
    inner: Mutex::new(ServerInner {
      status: initial_status(&config),
      config,
      provider: Arc::from(provider),
    }),
  }))
}

#[uniffi::export]
impl ServerHandle {
  pub fn start(&self) -> Result<(), CoreError> {
    let mut inner = self
      .inner
      .lock()
      .map_err(|_| CoreError::StateUnavailable)?;

    if inner.status.running {
      return Err(CoreError::AlreadyRunning);
    }

    inner.status = running_status(&inner.config);
    Ok(())
  }

  pub fn stop(&self) -> Result<(), CoreError> {
    let mut inner = self
      .inner
      .lock()
      .map_err(|_| CoreError::StateUnavailable)?;

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
use crate::error::CoreError;

#[derive(Debug, Clone, uniffi::Record)]
pub struct ProviderConfig {
  pub name: String,
  pub enabled: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ServerConfig {
  pub host: String,
  pub port: u16,
  pub enabled_providers: Vec<ProviderConfig>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ProviderRequest {
  pub provider: String,
  pub operation: String,
  pub payload_json: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ProviderResponse {
  pub ok: bool,
  pub payload_json: String,
  pub error_json: Option<String>,
}

pub fn validate_config(config: &ServerConfig) -> Result<(), CoreError> {
  let host = config.host.trim();
  if host.is_empty() {
    return Err(CoreError::InvalidConfig {
      message: "host must not be blank".into(),
    });
  }

  if !is_loopback_host(host) {
    return Err(CoreError::InvalidConfig {
      message: "host must be loopback".into(),
    });
  }

  if config.port == 0 {
    return Err(CoreError::InvalidConfig {
      message: "port must not be 0".into(),
    });
  }

  let mut seen = std::collections::HashSet::new();
  for provider in &config.enabled_providers {
    let name = provider.name.trim();
    if name.is_empty() {
      return Err(CoreError::InvalidConfig {
        message: "provider name must not be blank".into(),
      });
    }
    if !seen.insert(name.to_string()) {
      return Err(CoreError::InvalidConfig {
        message: format!("duplicate provider name: {name}"),
      });
    }
  }

  Ok(())
}

fn is_loopback_host(host: &str) -> bool {
  matches!(host, "127.0.0.1" | "localhost" | "::1")
}
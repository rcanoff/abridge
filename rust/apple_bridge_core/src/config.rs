use std::collections::HashSet;

use crate::{capabilities, error::CoreError};

#[derive(Debug, Clone, uniffi::Record)]
pub struct ProviderConfig {
  pub name: String,
  pub enabled: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ServerConfig {
  pub host: String,
  pub port: u16,
  pub bearer_token: String,
  pub enabled_providers: Vec<ProviderConfig>,
  pub enabled_capabilities: Vec<String>,
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

  if config.bearer_token.trim().is_empty() {
    return Err(CoreError::InvalidConfig {
      message: "bearer token must not be empty".into(),
    });
  }

  let mut seen_capabilities = HashSet::new();
  for capability in &config.enabled_capabilities {
    if !capabilities::is_valid_capability_id(capability) {
      return Err(CoreError::InvalidConfig {
        message: format!("invalid capability id: {capability}"),
      });
    }
    if !capabilities::is_allowed_in_v1(capability) {
      return Err(CoreError::InvalidConfig {
        message: format!("unsupported capability: {capability}"),
      });
    }
    if !seen_capabilities.insert(capability.clone()) {
      return Err(CoreError::InvalidConfig {
        message: format!("duplicate capability: {capability}"),
      });
    }
  }

  let mut seen = HashSet::new();
  for provider in &config.enabled_providers {
    let name = &provider.name;
    if name.trim().is_empty() {
      return Err(CoreError::InvalidConfig {
        message: "provider name must not be blank".into(),
      });
    }
    if !is_valid_provider_name(name) {
      return Err(CoreError::InvalidConfig {
        message: format!("invalid provider name: {name}"),
      });
    }
    if !seen.insert(name.clone()) {
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

fn is_valid_provider_name(name: &str) -> bool {
  !name.is_empty() && name == name.to_lowercase() && !name.chars().any(char::is_whitespace)
}

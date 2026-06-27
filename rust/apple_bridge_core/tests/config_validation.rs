use apple_bridge_core::{CoreError, ProviderConfig, ServerConfig, validate_config};

fn sample_config() -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port: 3020,
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
  }
}

#[test]
fn accepts_loopback_config() {
  assert!(validate_config(&sample_config()).is_ok());
}

#[test]
fn rejects_blank_host() {
  let mut config = sample_config();
  config.host = "  ".into();
  assert!(matches!(
    validate_config(&config),
    Err(CoreError::InvalidConfig { .. })
  ));
}

#[test]
fn rejects_wildcard_host() {
  let mut config = sample_config();
  config.host = "0.0.0.0".into();
  assert!(matches!(
    validate_config(&config),
    Err(CoreError::InvalidConfig { .. })
  ));
}

#[test]
fn rejects_port_zero() {
  let mut config = sample_config();
  config.port = 0;
  assert!(matches!(
    validate_config(&config),
    Err(CoreError::InvalidConfig { .. })
  ));
}

#[test]
fn rejects_duplicate_provider_names() {
  let mut config = sample_config();
  config.enabled_providers.push(ProviderConfig {
    name: "eventkit".into(),
    enabled: false,
  });
  assert!(matches!(
    validate_config(&config),
    Err(CoreError::InvalidConfig { .. })
  ));
}
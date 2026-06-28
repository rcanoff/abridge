use apple_bridge_core::{CoreError, ProviderConfig, ServerConfig, validate_config};

fn sample_config() -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port: 3020,
    bearer_token: "test-token".into(),
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
    enabled_capabilities: vec![],
  }
}

#[test]
fn accepts_loopback_config() {
  assert!(validate_config(&sample_config()).is_ok());
}

#[test]
fn accepts_localhost_hostname() {
  let mut config = sample_config();
  config.host = "localhost".into();
  assert!(validate_config(&config).is_ok());
}

#[test]
fn accepts_ipv6_loopback() {
  let mut config = sample_config();
  config.host = "::1".into();
  assert!(validate_config(&config).is_ok());
}

#[test]
fn rejects_blank_host() {
  let mut config = sample_config();
  config.host = "  ".into();
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_wildcard_host() {
  let mut config = sample_config();
  config.host = "0.0.0.0".into();
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_private_ip_host() {
  let mut config = sample_config();
  config.host = "192.168.1.10".into();
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_public_hostname() {
  let mut config = sample_config();
  config.host = "example.com".into();
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_port_zero() {
  let mut config = sample_config();
  config.port = 0;
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_uppercase_provider_name() {
  let mut config = sample_config();
  config.enabled_providers[0].name = "EventKit".into();
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_provider_name_with_spaces() {
  let mut config = sample_config();
  config.enabled_providers[0].name = "event kit".into();
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_whitespace_padded_provider_name() {
  let mut config = sample_config();
  config.enabled_providers[0].name = " eventkit ".into();
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn accepts_read_capability() {
  let mut config = sample_config();
  config.enabled_capabilities = vec!["eventkit.reminders.read".into()];
  assert!(validate_config(&config).is_ok());
}

#[test]
fn accepts_search_capability() {
  let mut config = sample_config();
  config.enabled_capabilities = vec!["eventkit.reminders.search".into()];
  assert!(validate_config(&config).is_ok());
}

#[test]
fn accepts_create_capability() {
  let mut config = sample_config();
  config.enabled_capabilities = vec!["eventkit.reminders.create".into()];
  assert!(validate_config(&config).is_ok());
}

#[test]
fn accepts_edit_capability() {
  let mut config = sample_config();
  config.enabled_capabilities = vec!["eventkit.reminders.edit".into()];
  assert!(validate_config(&config).is_ok());
}

#[test]
fn rejects_unknown_capability() {
  let mut config = sample_config();
  config.enabled_capabilities = vec!["eventkit.foo.bar".into()];
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_uppercase_capability() {
  let mut config = sample_config();
  config.enabled_capabilities = vec!["EventKit.Reminders.Read".into()];
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_whitespace_padded_capability() {
  let mut config = sample_config();
  config.enabled_capabilities = vec![" eventkit.reminders.read ".into()];
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_empty_bearer_token() {
  let mut config = sample_config();
  config.bearer_token = String::new();
  let err = validate_config(&config).expect_err("empty bearer token");
  assert!(matches!(err, CoreError::InvalidConfig { .. }));
  if let CoreError::InvalidConfig { message } = err {
    assert_eq!(message, "bearer token must not be empty");
  }
}

#[test]
fn rejects_whitespace_only_bearer_token() {
  let mut config = sample_config();
  config.bearer_token = "   ".into();
  let err = validate_config(&config).expect_err("whitespace bearer token");
  assert!(matches!(err, CoreError::InvalidConfig { .. }));
  if let CoreError::InvalidConfig { message } = err {
    assert_eq!(message, "bearer token must not be empty");
  }
}

#[test]
fn rejects_duplicate_provider_names() {
  let mut config = sample_config();
  config.enabled_providers.push(ProviderConfig {
    name: "eventkit".into(),
    enabled: false,
  });
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

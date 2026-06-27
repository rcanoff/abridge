use apple_bridge_core::CoreError;

#[test]
fn invalid_config_display() {
  let err = CoreError::InvalidConfig {
    message: "port must not be 0".into(),
  };
  assert_eq!(
    err.to_string(),
    "invalid configuration: port must not be 0"
  );
}
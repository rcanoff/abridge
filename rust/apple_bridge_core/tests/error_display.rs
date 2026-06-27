use apple_bridge_core::CoreError;

#[test]
fn invalid_config_display() {
  let err = CoreError::InvalidConfig {
    message: "port must not be 0".into(),
  };
  assert_eq!(err.to_string(), "invalid configuration: port must not be 0");
}

#[test]
fn bind_failed_display() {
  let err = CoreError::BindFailed {
    message: "address already in use".into(),
  };
  assert_eq!(err.to_string(), "failed to bind server: address already in use");
}

#[test]
fn runtime_failed_display() {
  let err = CoreError::RuntimeFailed {
    message: "worker threads unavailable".into(),
  };
  assert_eq!(err.to_string(), "failed to create runtime: worker threads unavailable");
}

#[test]
fn start_cancelled_display() {
  let err = CoreError::StartCancelled;
  assert_eq!(err.to_string(), "server start was cancelled");
}

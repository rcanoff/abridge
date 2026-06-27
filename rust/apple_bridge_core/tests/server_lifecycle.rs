mod support;

use apple_bridge_core::{
  create_server, server_status, start_server, stop_server, ProviderConfig, ServerConfig,
};
use support::mock_provider::MockProviderBridge;

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
fn lifecycle_start_stop() {
  let handle = create_server(sample_config(), Box::new(MockProviderBridge::new()))
    .expect("create_server");

  let before = server_status(handle.clone());
  assert!(!before.running);

  start_server(handle.clone()).expect("start");
  let running = server_status(handle.clone());
  assert!(running.running);
  assert_eq!(running.bound_host, "127.0.0.1");
  assert_eq!(running.bound_port, 3020);
  assert_eq!(running.provider_statuses.len(), 1);

  stop_server(handle.clone()).expect("stop");
  let stopped = server_status(handle);
  assert!(!stopped.running);
}

#[test]
fn start_twice_returns_already_running() {
  let handle = create_server(sample_config(), Box::new(MockProviderBridge::new()))
    .expect("create_server");
  start_server(handle.clone()).expect("first start");
  let err = start_server(handle).expect_err("second start");
  assert_eq!(err.to_string(), "server is already running");
}
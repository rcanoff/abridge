mod support;

use std::thread;
use std::time::Duration;

use apple_bridge_core::{
  create_server, server_status, start_server, stop_server, CoreError, ProviderConfig, ServerConfig,
};
use support::mock_provider::MockProviderBridge;
use support::port::allocate_test_port;

fn sample_config() -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port: allocate_test_port(),
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
  }
}

#[test]
fn lifecycle_start_stop() {
  let port = allocate_test_port();
  let config = ServerConfig {
    host: "127.0.0.1".into(),
    port,
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
  };
  let handle = create_server(config, Box::new(MockProviderBridge::new()))
    .expect("create_server");

  let before = server_status(handle.clone());
  assert!(!before.running);

  start_server(handle.clone()).expect("start");
  let running = server_status(handle.clone());
  assert!(running.running);
  assert_eq!(running.bound_host, "127.0.0.1");
  assert_eq!(running.bound_port, port);
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

#[test]
fn stop_during_start_leaves_consistent_status() {
  let port = allocate_test_port();
  let handle = create_server(
    ServerConfig {
      host: "127.0.0.1".into(),
      port,
      enabled_providers: vec![ProviderConfig {
        name: "eventkit".into(),
        enabled: true,
      }],
    },
    Box::new(MockProviderBridge::new()),
  )
  .expect("create_server");

  let starter = {
    let handle = handle.clone();
    thread::spawn(move || start_server(handle))
  };

  thread::sleep(Duration::from_millis(5));
  let _ = stop_server(handle.clone());

  let start_result = starter.join().expect("starter thread");
  assert!(matches!(
    start_result,
    Ok(()) | Err(CoreError::StartCancelled)
  ));

  let status = server_status(handle);
  assert!(!status.running);
}
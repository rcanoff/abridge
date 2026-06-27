mod support;

use std::sync::Mutex;
use std::thread;

use apple_bridge_core::{
  CoreError, ProviderConfig, ServerConfig, create_server, server_status, start_server, stop_server, test_sync,
};
use support::mock_provider::MockProviderBridge;
use support::port::allocate_test_port;

/// Serialize lifecycle tests: `test_sync` pause state is process-global.
static LIFECYCLE_TEST_LOCK: Mutex<()> = Mutex::new(());

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
  let _guard = LIFECYCLE_TEST_LOCK.lock().expect("lifecycle test lock");
  let port = allocate_test_port();
  let config = ServerConfig {
    host: "127.0.0.1".into(),
    port,
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
  };
  let handle = create_server(config, Box::new(MockProviderBridge::new())).expect("create_server");

  let before = server_status(handle.clone());
  assert!(!before.running);

  start_server(handle.clone()).expect("start");
  let running = server_status(handle.clone());
  assert!(running.running);
  assert_eq!(running.bound_host, "127.0.0.1");
  assert_eq!(running.bound_port, port);
  assert_eq!(running.provider_statuses.len(), 1);
  assert!(running.provider_statuses[0].healthy);

  stop_server(handle.clone()).expect("stop");
  let stopped = server_status(handle);
  assert!(!stopped.running);
}

#[test]
fn start_twice_returns_already_running() {
  let _guard = LIFECYCLE_TEST_LOCK.lock().expect("lifecycle test lock");
  let handle = create_server(sample_config(), Box::new(MockProviderBridge::new())).expect("create_server");
  start_server(handle.clone()).expect("first start");
  let err = start_server(handle).expect_err("second start");
  assert_eq!(err.to_string(), "server is already running");
}

#[test]
fn stop_during_start_releases_port_before_return() {
  let _guard = LIFECYCLE_TEST_LOCK.lock().expect("lifecycle test lock");
  let port = allocate_test_port();
  let config = ServerConfig {
    host: "127.0.0.1".into(),
    port,
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
  };
  let handle = create_server(config, Box::new(MockProviderBridge::new())).expect("create_server");

  test_sync::disarm();
  test_sync::arm_pause_before_bind();

  let starter = {
    let handle = handle.clone();
    thread::spawn(move || start_server(handle))
  };

  test_sync::wait_until_paused();

  let stopper = {
    let handle = handle.clone();
    thread::spawn(move || stop_server(handle))
  };

  test_sync::continue_paused_start();

  let start_result = starter.join().expect("starter thread");
  assert!(matches!(start_result, Ok(()) | Err(CoreError::StartCancelled)));
  stopper.join().expect("stopper thread").expect("stop during start");

  let status = server_status(handle.clone());
  assert!(!status.running);

  start_server(handle).expect("restart after stop-during-start completed");

  test_sync::disarm();
}

#[test]
fn concurrent_start_rejected_while_stop_awaits_start_completion() {
  let _guard = LIFECYCLE_TEST_LOCK.lock().expect("lifecycle test lock");
  let port = allocate_test_port();
  let config = ServerConfig {
    host: "127.0.0.1".into(),
    port,
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
  };
  let handle = create_server(config, Box::new(MockProviderBridge::new())).expect("create_server");

  test_sync::disarm();
  test_sync::arm_pause_before_bind();

  let starter = {
    let handle = handle.clone();
    thread::spawn(move || start_server(handle))
  };

  test_sync::wait_until_paused();

  let stopper = {
    let handle = handle.clone();
    thread::spawn(move || stop_server(handle))
  };

  let err = start_server(handle.clone()).expect_err("second start blocked during stop-during-start");
  assert_eq!(err.to_string(), "server is already running");

  test_sync::continue_paused_start();

  let start_result = starter.join().expect("starter thread");
  assert!(matches!(start_result, Ok(()) | Err(CoreError::StartCancelled)));
  stopper.join().expect("stopper thread").expect("stop during start");

  start_server(handle.clone()).expect("restart after stop-during-start");
  stop_server(handle).expect("final stop");

  test_sync::disarm();
}

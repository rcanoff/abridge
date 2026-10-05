mod support;

use abridge_core::{CoreError, ProviderConfig, ServerConfig, create_server, server_status, start_server, stop_server};
use support::mock_provider::MockProviderBridge;
use support::port::{allocate_test_port, allocate_test_port_for, health_body_ok, http_get_body, reserve_port};

fn config_on_port(host: &str, port: u16) -> ServerConfig {
  ServerConfig {
    host: host.into(),
    port,
    bearer_token: "test-token".into(),
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
    enabled_capabilities: vec![],
  }
}

#[test]
fn health_returns_ok_json() {
  let port = allocate_test_port();
  let handle =
    create_server(config_on_port("127.0.0.1", port), Box::new(MockProviderBridge::new())).expect("create_server");
  start_server(handle.clone()).expect("start");

  let (status_code, body) = http_get_body("/health", "127.0.0.1", port);
  assert_eq!(status_code, 200);
  assert!(health_body_ok(&body));

  stop_server(handle).expect("stop");
}

#[test]
fn health_on_ipv6_loopback() {
  let port = allocate_test_port_for("::1");
  let handle = create_server(config_on_port("::1", port), Box::new(MockProviderBridge::new())).expect("create_server");
  start_server(handle.clone()).expect("start");

  let (status_code, body) = http_get_body("/health", "::1", port);
  assert_eq!(status_code, 200);
  assert!(health_body_ok(&body));

  stop_server(handle).expect("stop");
}

#[test]
fn stop_releases_port_for_rebind() {
  let port = allocate_test_port();
  let handle =
    create_server(config_on_port("127.0.0.1", port), Box::new(MockProviderBridge::new())).expect("create_server");
  start_server(handle.clone()).expect("first start");
  stop_server(handle.clone()).expect("stop");
  start_server(handle).expect("second start after stop");
}

#[test]
fn bind_failure_when_port_in_use() {
  let reserved = reserve_port();
  let port = reserved.port;
  let first =
    create_server(config_on_port("127.0.0.1", port), Box::new(MockProviderBridge::new())).expect("first server");
  start_server(first.clone()).expect_err("bind fails while port reserved");

  drop(reserved);
  start_server(first.clone()).expect("first start after release");

  let second =
    create_server(config_on_port("127.0.0.1", port), Box::new(MockProviderBridge::new())).expect("second server");
  let err = start_server(second.clone()).expect_err("second bind");
  assert!(matches!(err, CoreError::BindFailed { .. }));

  let status = server_status(second);
  assert!(!status.running);
  assert!(status.last_error.is_some());

  stop_server(first).expect("stop first server");
}

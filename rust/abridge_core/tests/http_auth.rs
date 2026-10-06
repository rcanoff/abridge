mod support;

use abridge_core::{ProviderConfig, ServerConfig, create_server, start_server, stop_server};
use support::mock_provider::MockProviderBridge;
use support::port::{
  allocate_test_port, health_body_ok, http_get_body, http_post, http_post_raw,
  response_includes_www_authenticate_bearer,
};

const TEST_TOKEN: &str = "integration-test-token";

fn config_on_port(port: u16) -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port,
    bearer_token: TEST_TOKEN.into(),
    app_version: "test".into(),
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
    enabled_capabilities: vec![],
  }
}

#[test]
fn health_does_not_require_auth() {
  let port = allocate_test_port();
  let handle = create_server(config_on_port(port), Box::new(MockProviderBridge::new())).expect("create_server");
  start_server(handle.clone()).expect("start");

  let (status_code, body) = http_get_body("/health", "127.0.0.1", port);
  assert_eq!(status_code, 200);
  assert!(health_body_ok(&body));

  stop_server(handle).expect("stop");
}

#[test]
fn mcp_without_auth_returns_unauthorized() {
  let port = allocate_test_port();
  let handle = create_server(config_on_port(port), Box::new(MockProviderBridge::new())).expect("create_server");
  start_server(handle.clone()).expect("start");

  let (status_code, body) = http_post("/mcp", "127.0.0.1", port, "{}", None);
  assert_eq!(status_code, 401);
  assert!(body.contains("unauthorized"));

  let raw = http_post_raw("/mcp", "127.0.0.1", port, "{}", None);
  assert!(response_includes_www_authenticate_bearer(&raw));

  stop_server(handle).expect("stop");
}

#[test]
fn mcp_with_wrong_token_returns_unauthorized() {
  let port = allocate_test_port();
  let handle = create_server(config_on_port(port), Box::new(MockProviderBridge::new())).expect("create_server");
  start_server(handle.clone()).expect("start");

  let (status_code, body) = http_post("/mcp", "127.0.0.1", port, "{}", Some("wrong-token"));
  assert_eq!(status_code, 401);
  assert!(body.contains("unauthorized"));

  stop_server(handle).expect("stop");
}

#[test]
fn mcp_with_valid_token_returns_json_rpc_response() {
  let port = allocate_test_port();
  let handle = create_server(config_on_port(port), Box::new(MockProviderBridge::new())).expect("create_server");
  start_server(handle.clone()).expect("start");

  let body = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#;
  let (status_code, body) = http_post("/mcp", "127.0.0.1", port, body, Some(TEST_TOKEN));
  assert_eq!(status_code, 200);
  assert!(body.contains(r#""protocolVersion":"2024-11-05""#));

  stop_server(handle).expect("stop");
}

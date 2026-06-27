mod support;

use apple_bridge_core::{ProviderConfig, ServerConfig, create_server, start_server, stop_server};
use support::mock_provider::MockProviderBridge;
use support::port::{allocate_test_port, http_post_json};

const TEST_TOKEN: &str = "integration-test-token";
const PROTOCOL_VERSION: &str = "2024-11-05";

fn config_on_port(port: u16, enabled_capabilities: Vec<String>) -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port,
    bearer_token: TEST_TOKEN.into(),
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
    enabled_capabilities,
  }
}

fn mcp_post(body: &str, port: u16, mock: &MockProviderBridge) -> (u16, String) {
  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.read".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let result = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");
  result
}

#[test]
fn mcp_initialize_returns_protocol_version() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = format!(
    r#"{{"jsonrpc":"2.0","id":1,"method":"initialize","params":{{"protocolVersion":"{PROTOCOL_VERSION}","capabilities":{{}},"clientInfo":{{"name":"t","version":"0"}}}}}}"#
  );
  let (status, resp) = mcp_post(&body, port, &mock);
  assert_eq!(status, 200);
  assert!(resp.contains(&format!(r#""protocolVersion":"{PROTOCOL_VERSION}""#)));
}

#[test]
fn mcp_initialize_returns_server_protocol_not_client_echo() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#;
  let (status, resp) = mcp_post(body, port, &mock);
  assert_eq!(status, 200);
  assert!(resp.contains(&format!(r#""protocolVersion":"{PROTOCOL_VERSION}""#)));
  assert!(!resp.contains(r#""protocolVersion":"2099-01-01""#));
}

#[test]
fn mcp_tools_list_filtered_by_capability() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#;

  let handle_with_read = create_server(
    config_on_port(port, vec!["eventkit.reminders.read".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle_with_read.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle_with_read).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("eventkit.reminders.list_lists"));
  assert!(resp.contains("eventkit.reminders.list_reminders"));

  let port_empty = allocate_test_port();
  let handle_empty =
    create_server(config_on_port(port_empty, vec![]), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle_empty.clone()).expect("start");
  let (status_empty, resp_empty) = http_post_json("/mcp", "127.0.0.1", port_empty, body, TEST_TOKEN);
  stop_server(handle_empty).expect("stop");

  assert_eq!(status_empty, 200);
  assert!(resp_empty.contains(r#""tools":[]"#));
}

#[test]
fn mcp_tools_list_excludes_disabled_provider() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    ServerConfig {
      host: "127.0.0.1".into(),
      port,
      bearer_token: TEST_TOKEN.into(),
      enabled_providers: vec![ProviderConfig {
        name: "eventkit".into(),
        enabled: false,
      }],
      enabled_capabilities: vec!["eventkit.reminders.read".into()],
    },
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains(r#""tools":[]"#));
  assert!(!resp.contains("eventkit.reminders.list_lists"));
  assert!(!resp.contains("eventkit.reminders.list_reminders"));
}

#[test]
fn tools_call_dispatches_to_provider() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"eventkit.reminders.list_lists","arguments":{}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.read".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains(r#""isError":false"#));
  let recorded = mock.last_request.lock().expect("lock").clone().expect("request");
  assert_eq!(recorded.provider, "eventkit");
  assert_eq!(recorded.operation, "list_lists");
  assert_eq!(recorded.payload_json, "{}");
}

#[test]
fn tools_call_capability_disabled_without_provider_call() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"eventkit.reminders.list_lists","arguments":{}}}"#;

  let handle = create_server(config_on_port(port, vec![]), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains(r#""isError":true"#));
  assert!(resp.contains("capability_disabled"));
  assert_eq!(*mock.call_count.lock().expect("lock"), 0);
}

#[test]
fn tools_call_unknown_tool() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#;

  let (status, resp) = mcp_post(body, port, &mock);

  assert_eq!(status, 200);
  assert!(resp.contains(r#""isError":true"#));
  assert!(resp.contains("unknown_tool"));
  assert_eq!(*mock.call_count.lock().expect("lock"), 0);
}

mod support;

use abridge_core::{ProviderConfig, ServerConfig, create_server, start_server, stop_server};
use support::mock_provider::MockProviderBridge;
use support::port::{allocate_test_port, http_post_json};

const TEST_TOKEN: &str = "integration-test-token";

fn config_on_port(port: u16) -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port,
    bearer_token: TEST_TOKEN.into(),
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
    enabled_capabilities: vec!["eventkit.reminders.read".into()],
  }
}

#[test]
fn tools_call_produces_audit_entry() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"eventkit.reminders.list_lists","arguments":{}}}"#;

  let handle = create_server(config_on_port(port), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, _resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle.clone()).expect("stop");

  assert_eq!(status, 200);

  let entries = handle.usage_audit_entries();
  let tool_call = entries
    .iter()
    .find(|entry| entry.event_type == "tool_call")
    .expect("tool_call audit entry");
  assert_eq!(tool_call.tool_name.as_deref(), Some("eventkit.reminders.list_lists"));
  assert!(tool_call.success);
  assert!(tool_call.duration_ms.is_some());
}

#[test]
fn initialize_produces_mcp_initialize_entry() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#;

  let handle = create_server(config_on_port(port), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, _resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle.clone()).expect("stop");

  assert_eq!(status, 200);

  let entries = handle.usage_audit_entries();
  let initialize = entries
    .iter()
    .find(|entry| entry.event_type == "mcp_initialize")
    .expect("mcp_initialize audit entry");
  assert!(initialize.success);
  assert!(initialize.tool_name.is_none());
  assert!(initialize.duration_ms.is_none());
}

#[test]
fn lifecycle_events_recorded_on_start_and_stop() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();

  let handle = create_server(config_on_port(port), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle.clone()).expect("start");
  stop_server(handle.clone()).expect("stop");

  let entries = handle.usage_audit_entries();
  let event_types: Vec<&str> = entries.iter().map(|entry| entry.event_type.as_str()).collect();

  assert!(event_types.contains(&"port_bind"));
  assert!(event_types.contains(&"server_start"));
  assert!(event_types.contains(&"server_stop"));
}

#[test]
fn disabled_logging_skips_new_records() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();

  let handle = create_server(config_on_port(port), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle.clone()).expect("start");
  let count_after_start = handle.usage_audit_entries().len();

  handle.set_usage_logging_enabled(false);
  assert!(!handle.usage_logging_enabled());

  let body = r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"eventkit.reminders.list_lists","arguments":{}}}"#;
  let (status, _resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle.clone()).expect("stop");

  assert_eq!(status, 200);
  assert_eq!(handle.usage_audit_entries().len(), count_after_start);
}

#[test]
fn record_api_key_rotation_via_uniffi_surface() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();

  let handle = create_server(config_on_port(port), Box::new(mock.clone_for_server())).expect("create_server");

  handle.record_api_key_rotation();

  let entries = handle.usage_audit_entries();
  let rotation = entries
    .iter()
    .find(|entry| entry.event_type == "api_key_rotation")
    .expect("api_key_rotation audit entry");
  assert!(rotation.success);
}

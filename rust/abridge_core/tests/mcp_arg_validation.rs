//! Phase A1: invalid tool arguments must fail in Rust before ProviderBridge is called.

mod support;

use abridge_core::{ProviderConfig, ServerConfig, create_server, start_server, stop_server};
use serde_json::Value;
use support::mock_provider::MockProviderBridge;
use support::port::{allocate_test_port, http_post_json};

const TEST_TOKEN: &str = "integration-test-token";

fn eventkit_config(port: u16, capabilities: Vec<String>) -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port,
    bearer_token: TEST_TOKEN.into(),
    app_version: "test".into(),
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
    enabled_capabilities: capabilities,
  }
}

fn tools_call(port: u16, mock: &MockProviderBridge, capabilities: Vec<String>, body: &str) -> (u16, String) {
  let handle =
    create_server(eventkit_config(port, capabilities), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle.clone()).expect("start");
  let result = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");
  result
}

fn tool_call_error_code(resp: &str) -> Option<String> {
  let envelope: Value = serde_json::from_str(resp).ok()?;
  let result = envelope.get("result")?;
  assert_eq!(result.get("isError")?.as_bool(), Some(true));
  let text = result.get("content")?.as_array()?.first()?.get("text")?.as_str()?;
  let err: Value = serde_json::from_str(text).ok()?;
  err.get("code")?.as_str().map(str::to_owned)
}

#[test]
fn invalid_get_event_args_do_not_call_provider_bridge() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  // inputSchema requires event_identifier — omit it.
  let body =
    r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"eventkit.events.get_event","arguments":{}}}"#;

  let (status, resp) = tools_call(port, &mock, vec!["eventkit.events.read".into()], body);

  assert_eq!(status, 200);
  let count = *mock.call_count.lock().expect("lock");
  assert_eq!(count, 0, "ProviderBridge must not run when args fail inputSchema");
  assert_eq!(
    tool_call_error_code(&resp).as_deref(),
    Some("invalid_arguments"),
    "resp={resp}"
  );
}

#[test]
fn invalid_create_event_args_do_not_call_provider_bridge() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  // Missing required title, start_date, end_date (only calendar_identifier).
  let body = r#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"eventkit.events.create_event","arguments":{"calendar_identifier":"cal-1"}}}"#;

  let (status, resp) = tools_call(port, &mock, vec!["eventkit.events.create".into()], body);

  assert_eq!(status, 200);
  assert_eq!(*mock.call_count.lock().expect("lock"), 0);
  assert_eq!(tool_call_error_code(&resp).as_deref(), Some("invalid_arguments"));
}

#[test]
fn valid_list_lists_args_call_provider_bridge() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"eventkit.reminders.list_lists","arguments":{}}}"#;

  let (status, resp) = tools_call(port, &mock, vec!["eventkit.reminders.read".into()], body);

  assert_eq!(status, 200);
  assert_eq!(*mock.call_count.lock().expect("lock"), 1);
  let envelope: Value = serde_json::from_str(&resp).expect("json");
  assert_eq!(
    envelope.pointer("/result/isError").and_then(Value::as_bool),
    Some(false)
  );
}

#[test]
fn valid_get_event_args_call_provider_bridge() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"eventkit.events.get_event","arguments":{"event_identifier":"evt-1"}}}"#;

  let (status, resp) = tools_call(port, &mock, vec!["eventkit.events.read".into()], body);

  assert_eq!(status, 200);
  assert_eq!(*mock.call_count.lock().expect("lock"), 1);
  let envelope: Value = serde_json::from_str(&resp).expect("json");
  assert_eq!(
    envelope.pointer("/result/isError").and_then(Value::as_bool),
    Some(false)
  );
}

mod support;

use abridge_core::{ProviderConfig, ServerConfig, create_server, start_server, stop_server};
use serde_json::Value;
use support::mock_provider::MockProviderBridge;
use support::port::{allocate_test_port, http_post, http_post_json};

const TEST_TOKEN: &str = "integration-test-token";
const TOOL_NAME: &str = "diagnostics.get_usage_log";

fn diagnostics_config(port: u16) -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port,
    bearer_token: TEST_TOKEN.into(),
    app_version: "test".into(),
    enabled_providers: vec![ProviderConfig {
      name: "diagnostics".into(),
      enabled: true,
    }],
    enabled_capabilities: vec!["diagnostics.read".into()],
  }
}

fn call_get_usage_log(
  port: u16,
  mock: &MockProviderBridge,
  arguments: &str,
  bearer_token: Option<&str>,
) -> (u16, String) {
  let handle = create_server(diagnostics_config(port), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle.clone()).expect("start");
  let body = format!(
    r#"{{"jsonrpc":"2.0","id":42,"method":"tools/call","params":{{"name":"{TOOL_NAME}","arguments":{arguments}}}}}"#
  );
  let result = http_post("/mcp", "127.0.0.1", port, &body, bearer_token);
  stop_server(handle).expect("stop");
  result
}

fn parse_tool_result_payload(response: &str) -> Value {
  let envelope: Value = serde_json::from_str(response).expect("json-rpc envelope");
  let text = envelope
    .pointer("/result/content/0/text")
    .and_then(Value::as_str)
    .expect("tool result text");
  serde_json::from_str(text).expect("tool payload json")
}

#[test]
fn get_usage_log_requires_bearer_auth() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();

  let (status, body) = call_get_usage_log(port, &mock, "{}", None);

  assert_eq!(status, 401);
  assert!(body.contains("unauthorized"));
  assert_eq!(*mock.call_count.lock().expect("lock"), 0);
}

#[test]
fn get_usage_log_response_shape_and_no_sensitive_tokens() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();

  let (status, response) = call_get_usage_log(port, &mock, "{}", Some(TEST_TOKEN));
  assert_eq!(status, 200);
  assert!(response.contains(r#""isError":false"#));

  let payload = parse_tool_result_payload(&response);
  assert_eq!(payload.get("logging_enabled").and_then(Value::as_bool), Some(true));

  let entries = payload.get("entries").and_then(Value::as_array).expect("entries array");
  assert!(!entries.is_empty());

  let lowered = response.to_lowercase();
  assert!(!lowered.contains("bearer"));
  assert!(!lowered.contains("token"));
  assert!(!lowered.contains("payload"));

  let first = entries.first().expect("first entry");
  assert!(first.get("timestamp_utc").is_some());
  assert!(first.get("event_type").is_some());
  assert!(first.get("success").is_some());
  assert_eq!(*mock.call_count.lock().expect("lock"), 0);
}

#[test]
fn get_usage_log_respects_limit() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();

  let init_body = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#;
  let handle = create_server(diagnostics_config(port), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle.clone()).expect("start");
  let (init_status, _) = http_post_json("/mcp", "127.0.0.1", port, init_body, TEST_TOKEN);
  assert_eq!(init_status, 200);

  let call_body = format!(
    r#"{{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{{"name":"{TOOL_NAME}","arguments":{{"limit":1}}}}}}"#
  );
  let (status, response) = http_post_json("/mcp", "127.0.0.1", port, &call_body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  let payload = parse_tool_result_payload(&response);
  let entries = payload.get("entries").and_then(Value::as_array).expect("entries array");
  assert_eq!(entries.len(), 1);
  assert_eq!(entries[0].get("event_type").and_then(Value::as_str), Some("tool_call"));
  assert_eq!(entries[0].get("tool_name").and_then(Value::as_str), Some(TOOL_NAME));
}

#[test]
fn get_usage_log_when_logging_disabled_returns_prior_entries() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();

  let handle = create_server(diagnostics_config(port), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle.clone()).expect("start");
  let count_after_start = handle.usage_audit_entries().len();
  assert!(count_after_start > 0);

  handle.set_usage_logging_enabled(false);
  assert!(!handle.usage_logging_enabled());

  let call_body =
    format!(r#"{{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{{"name":"{TOOL_NAME}","arguments":{{}}}}}}"#);
  let (status, response) = http_post_json("/mcp", "127.0.0.1", port, &call_body, TEST_TOKEN);
  stop_server(handle.clone()).expect("stop");

  assert_eq!(status, 200);
  let payload = parse_tool_result_payload(&response);
  assert_eq!(payload.get("logging_enabled").and_then(Value::as_bool), Some(false));

  let entries = payload.get("entries").and_then(Value::as_array).expect("entries array");
  assert_eq!(entries.len(), count_after_start);
  assert_eq!(*mock.call_count.lock().expect("lock"), 0);
}

#[test]
fn tools_list_includes_get_usage_log_when_diagnostics_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#;

  let handle = create_server(diagnostics_config(port), Box::new(mock.clone_for_server())).expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains(r#""name":"diagnostics_get_usage_log""#));
}

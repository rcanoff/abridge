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
fn tools_call_dispatches_list_reminders() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"eventkit.reminders.list_reminders","arguments":{"list_id":"list-1"}}}"#;

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
  assert_eq!(recorded.operation, "list_reminders");
  assert!(recorded.payload_json.contains("list-1"));
}

#[test]
fn tools_call_dispatches_get_reminder() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"eventkit.reminders.get_reminder","arguments":{"reminder_id":"rem-42"}}}"#;

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
  assert_eq!(recorded.operation, "get_reminder");
  assert!(recorded.payload_json.contains("rem-42"));
}

#[test]
fn mcp_tools_list_includes_search_reminders_when_search_capability_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":13,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.search".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("eventkit.reminders.search_reminders"));
  assert!(!resp.contains("eventkit.reminders.list_reminders"));
}

#[test]
fn tools_call_dispatches_search_reminders() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"eventkit.reminders.search_reminders","arguments":{"completion_status":"incomplete","calendar_identifier":"list-1"}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.search".into()]),
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
  assert_eq!(recorded.operation, "search_reminders");
  assert!(recorded.payload_json.contains("incomplete"));
  assert!(recorded.payload_json.contains("calendar_identifier"));
  assert!(recorded.payload_json.contains("list-1"));
}

#[test]
fn mcp_tools_list_includes_get_reminder() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":12,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.read".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("eventkit.reminders.get_reminder"));
}

#[test]
fn mcp_tools_list_includes_create_reminder_when_create_capability_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":15,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.create".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("eventkit.reminders.create_reminder"));
  assert!(resp.contains("eventkit.reminders.create_list"));
  assert!(!resp.contains("eventkit.reminders.list_reminders"));
}

#[test]
fn tools_call_dispatches_create_reminder() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":16,"method":"tools/call","params":{"name":"eventkit.reminders.create_reminder","arguments":{"calendar_identifier":"list-1","title":"Buy milk","notes":"2%","priority":5}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.create".into()]),
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
  assert_eq!(recorded.operation, "create_reminder");
  assert!(recorded.payload_json.contains("list-1"));
  assert!(recorded.payload_json.contains("Buy milk"));
  assert!(recorded.payload_json.contains("notes"));
}

#[test]
fn mcp_tools_list_includes_update_reminder_when_edit_capability_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":18,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.edit".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("eventkit.reminders.update_reminder"));
  assert!(resp.contains("eventkit.reminders.move_reminder"));
  assert!(!resp.contains("eventkit.reminders.create_reminder"));
}

#[test]
fn tools_call_dispatches_move_reminder() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":20,"method":"tools/call","params":{"name":"eventkit.reminders.move_reminder","arguments":{"reminder_id":"rem-42","calendar_identifier":"list-2"}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.edit".into()]),
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
  assert_eq!(recorded.operation, "move_reminder");
  assert!(recorded.payload_json.contains("rem-42"));
  assert!(recorded.payload_json.contains("list-2"));
}

#[test]
fn tools_call_dispatches_update_reminder() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":19,"method":"tools/call","params":{"name":"eventkit.reminders.update_reminder","arguments":{"reminder_id":"rem-42","title":"Updated title","notes":"2%","priority":4}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.edit".into()]),
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
  assert_eq!(recorded.operation, "update_reminder");
  assert!(recorded.payload_json.contains("rem-42"));
  assert!(recorded.payload_json.contains("Updated title"));
  assert!(recorded.payload_json.contains("notes"));
}

#[test]
fn mcp_tools_list_includes_complete_tools_when_complete_capability_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":21,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.complete".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("eventkit.reminders.complete_reminder"));
  assert!(resp.contains("eventkit.reminders.uncomplete_reminder"));
  assert!(!resp.contains("eventkit.reminders.update_reminder"));
}

#[test]
fn tools_call_dispatches_complete_reminder() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":22,"method":"tools/call","params":{"name":"eventkit.reminders.complete_reminder","arguments":{"reminder_id":"rem-42"}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.complete".into()]),
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
  assert_eq!(recorded.operation, "complete_reminder");
  assert!(recorded.payload_json.contains("rem-42"));
}

#[test]
fn tools_call_dispatches_uncomplete_reminder() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"eventkit.reminders.uncomplete_reminder","arguments":{"reminder_id":"rem-99"}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.complete".into()]),
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
  assert_eq!(recorded.operation, "uncomplete_reminder");
  assert!(recorded.payload_json.contains("rem-99"));
}

#[test]
fn mcp_tools_list_includes_set_reminder_alarms_when_alarms_capability_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":24,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.alarms".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("eventkit.reminders.set_reminder_alarms"));
  assert!(!resp.contains("eventkit.reminders.update_reminder"));
}

#[test]
fn tools_call_dispatches_set_reminder_alarms() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":25,"method":"tools/call","params":{"name":"eventkit.reminders.set_reminder_alarms","arguments":{"reminder_id":"rem-42","alarms":[{"relative_offset":-300}]}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.alarms".into()]),
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
  assert_eq!(recorded.operation, "set_reminder_alarms");
  assert!(recorded.payload_json.contains("rem-42"));
  assert!(recorded.payload_json.contains("relative_offset"));
}

#[test]
fn mcp_tools_list_includes_set_reminder_recurrence_when_recurrence_capability_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":26,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.recurrence".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("eventkit.reminders.set_reminder_recurrence"));
  assert!(!resp.contains("eventkit.reminders.update_reminder"));
}

#[test]
fn tools_call_dispatches_set_reminder_recurrence() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":27,"method":"tools/call","params":{"name":"eventkit.reminders.set_reminder_recurrence","arguments":{"reminder_id":"rem-42","recurrence_rules":[{"frequency":"daily","interval":1}]}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.recurrence".into()]),
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
  assert_eq!(recorded.operation, "set_reminder_recurrence");
  assert!(recorded.payload_json.contains("rem-42"));
  assert!(recorded.payload_json.contains("recurrence_rules"));
}

#[test]
fn mcp_tools_list_includes_delete_reminder_when_delete_capability_enabled() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":28,"method":"tools/list","params":{}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.delete".into()]),
    Box::new(mock.clone_for_server()),
  )
  .expect("create_server");
  start_server(handle.clone()).expect("start");
  let (status, resp) = http_post_json("/mcp", "127.0.0.1", port, body, TEST_TOKEN);
  stop_server(handle).expect("stop");

  assert_eq!(status, 200);
  assert!(resp.contains("eventkit.reminders.delete_reminder"));
  assert!(!resp.contains("eventkit.reminders.update_reminder"));
}

#[test]
fn tools_call_dispatches_delete_reminder() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":29,"method":"tools/call","params":{"name":"eventkit.reminders.delete_reminder","arguments":{"reminder_id":"rem-42"}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.delete".into()]),
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
  assert_eq!(recorded.operation, "delete_reminder");
  assert!(recorded.payload_json.contains("rem-42"));
}

#[test]
fn tools_call_dispatches_create_list() {
  let port = allocate_test_port();
  let mock = MockProviderBridge::new();
  let body = r#"{"jsonrpc":"2.0","id":17,"method":"tools/call","params":{"name":"eventkit.reminders.create_list","arguments":{"title":"Shopping","source_identifier":"src-local"}}}"#;

  let handle = create_server(
    config_on_port(port, vec!["eventkit.reminders.create".into()]),
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
  assert_eq!(recorded.operation, "create_list");
  assert!(recorded.payload_json.contains("Shopping"));
  assert!(recorded.payload_json.contains("source_identifier"));
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

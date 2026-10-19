//! JSON-RPC types and constants for the MCP HTTP transport.

pub const JSONRPC_VERSION: &str = "2.0";
pub const PROTOCOL_VERSION: &str = "2024-11-05";
pub const SERVER_NAME: &str = "abridge";

/// Workflow index returned by `initialize`. Clients can show this before inlining every schema.
pub const SERVER_INSTRUCTIONS: &str = "Events: eventkit_events_search_events for a title, or \
eventkit_events_list_events for a date window. Reminders: eventkit_reminders_search_reminders. \
Contacts: contacts_search_contacts. Notes: notes_search_notes, then notes_get_note for the body; \
notes_get_attachment directly when a search match names an attachment. Places: \
mapkit_search_places, then mapkit_estimate_travel_time. A local image: vision_recognize_text with \
image_path. Folder paths: notes_list_folders. Absent keys mean null, false, or empty; 0 is kept. \
Diagnostics keeps false success and logging_enabled. corelocation_get_current_location, paths, and \
an unspecified clock are this server Mac's, not the caller's.";

pub const INVALID_REQUEST: i64 = -32600;
pub const METHOD_NOT_FOUND: i64 = -32601;

pub fn json_rpc_result(id: serde_json::Value, result: serde_json::Value) -> serde_json::Value {
  serde_json::json!({
    "jsonrpc": JSONRPC_VERSION,
    "id": id,
    "result": result
  })
}

pub fn json_rpc_error(id: Option<serde_json::Value>, code: i64, message: &str) -> serde_json::Value {
  serde_json::json!({
    "jsonrpc": JSONRPC_VERSION,
    "id": id,
    "error": {
      "code": code,
      "message": message
    }
  })
}

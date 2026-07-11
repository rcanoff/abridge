//! Typed / normalized tool arguments for high-traffic EventKit create/update tools (Phase C).
//!
//! After JSON Schema validation, selected tools deserialize into typed structs and
//! re-serialize for the Swift bridge. This keeps the FFI JSON contract while moving
//! structure ownership to Rust. Unknown tools pass arguments through unchanged.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::tools::{self, ToolDefinition};

/// Normalize arguments for tools that have a typed path. On success returns JSON to
/// forward to `ProviderBridge`. On type failure returns an error message.
pub fn normalize_tool_arguments(tool: &ToolDefinition, arguments: Value) -> Result<Value, String> {
  match tool.name {
    tools::TOOL_CREATE_REMINDER => normalize_typed::<CreateReminderArgs>(arguments, "create_reminder"),
    tools::TOOL_CREATE_EVENT => normalize_typed::<CreateEventArgs>(arguments, "create_event"),
    tools::TOOL_UPDATE_REMINDER => normalize_typed::<UpdateReminderArgs>(arguments, "update_reminder"),
    tools::TOOL_UPDATE_EVENT => normalize_typed::<UpdateEventArgs>(arguments, "update_event"),
    _ => Ok(arguments),
  }
}

fn normalize_typed<T>(arguments: Value, label: &str) -> Result<Value, String>
where
  T: for<'de> Deserialize<'de> + Serialize,
{
  let typed: T = serde_json::from_value(arguments).map_err(|err| format!("typed {label} args: {err}"))?;
  serde_json::to_value(typed).map_err(|err| format!("serialize {label} args: {err}"))
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct CreateReminderArgs {
  calendar_identifier: String,
  title: String,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  notes: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  location: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  url: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  priority: Option<i64>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  due_date_components: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  start_date_components: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  time_zone: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  is_completed: Option<bool>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  completion_date: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  alarms: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  recurrence_rules: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct CreateEventArgs {
  calendar_identifier: String,
  title: String,
  start_date: String,
  end_date: String,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  notes: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  location: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  url: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  time_zone: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  is_all_day: Option<bool>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  availability: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  structured_location: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  alarms: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  recurrence_rules: Option<Value>,
}

/// Update payloads keep nested/optional JSON as `Value` so null vs omit is preserved.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct UpdateReminderArgs {
  calendar_item_identifier: String,
  #[serde(flatten)]
  rest: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct UpdateEventArgs {
  event_identifier: String,
  #[serde(flatten)]
  rest: Value,
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::tools::resolve_tool;
  use serde_json::json;

  #[test]
  fn create_reminder_round_trips_required_fields() {
    let tool = resolve_tool(tools::TOOL_CREATE_REMINDER).expect("tool");
    let input = json!({
      "calendar_identifier": "list-1",
      "title": "Buy milk",
      "priority": 5
    });
    let out = normalize_tool_arguments(tool, input).expect("ok");
    assert_eq!(out["calendar_identifier"], "list-1");
    assert_eq!(out["title"], "Buy milk");
    assert_eq!(out["priority"], 5);
  }

  #[test]
  fn create_event_round_trips_required_fields() {
    let tool = resolve_tool(tools::TOOL_CREATE_EVENT).expect("tool");
    let input = json!({
      "calendar_identifier": "cal-1",
      "title": "Meeting",
      "start_date": "2024-01-15T12:00:00Z",
      "end_date": "2024-01-15T13:00:00Z"
    });
    let out = normalize_tool_arguments(tool, input).expect("ok");
    assert_eq!(out["title"], "Meeting");
    assert_eq!(out["start_date"], "2024-01-15T12:00:00Z");
  }

  #[test]
  fn update_event_requires_event_identifier() {
    let tool = resolve_tool(tools::TOOL_UPDATE_EVENT).expect("tool");
    let out = normalize_tool_arguments(
      tool,
      json!({
        "event_identifier": "evt-1",
        "title": "Renamed"
      }),
    )
    .expect("ok");
    assert_eq!(out["event_identifier"], "evt-1");
    assert_eq!(out["title"], "Renamed");
  }

  #[test]
  fn untyped_tools_pass_through() {
    let tool = resolve_tool(tools::TOOL_LIST_LISTS).expect("tool");
    let input = json!({});
    let out = normalize_tool_arguments(tool, input.clone()).expect("ok");
    assert_eq!(out, input);
  }

  #[test]
  fn create_reminder_typed_path_rejects_wrong_priority_type() {
    let tool = resolve_tool(tools::TOOL_CREATE_REMINDER).expect("tool");
    let err = normalize_tool_arguments(
      tool,
      json!({
        "calendar_identifier": "list-1",
        "title": "X",
        "priority": true
      }),
    )
    .expect_err("type");
    assert!(err.contains("typed create_reminder"), "{err}");
  }
}

//! MCP tool registry — name, capability, provider dispatch.

use crate::capabilities;

pub const TOOL_LIST_LISTS: &str = "eventkit.reminders.list_lists";
pub const TOOL_LIST_REMINDERS: &str = "eventkit.reminders.list_reminders";
pub const TOOL_GET_REMINDER: &str = "eventkit.reminders.get_reminder";
pub const TOOL_SEARCH_REMINDERS: &str = "eventkit.reminders.search_reminders";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ToolDefinition {
  pub name: &'static str,
  pub capability: &'static str,
  pub provider: &'static str,
  pub operation: &'static str,
  pub description: &'static str,
}

const ALL_TOOLS: [ToolDefinition; 4] = [
  ToolDefinition {
    name: TOOL_LIST_LISTS,
    capability: capabilities::EVENTKIT_REMINDERS_READ,
    provider: "eventkit",
    operation: "list_lists",
    description: "List reminder lists (calendars)",
  },
  ToolDefinition {
    name: TOOL_LIST_REMINDERS,
    capability: capabilities::EVENTKIT_REMINDERS_READ,
    provider: "eventkit",
    operation: "list_reminders",
    description: "List reminders, optionally filtered by list_id",
  },
  ToolDefinition {
    name: TOOL_GET_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_READ,
    provider: "eventkit",
    operation: "get_reminder",
    description: "Get a single reminder by reminder_id",
  },
  ToolDefinition {
    name: TOOL_SEARCH_REMINDERS,
    capability: capabilities::EVENTKIT_REMINDERS_SEARCH,
    provider: "eventkit",
    operation: "search_reminders",
    description: "Search reminders with completion, due-date, list, and text filters",
  },
];

pub fn all_tools() -> &'static [ToolDefinition] {
  &ALL_TOOLS
}

pub fn tools_for_capabilities(enabled: &[String]) -> Vec<&'static ToolDefinition> {
  all_tools()
    .iter()
    .filter(|tool| enabled.iter().any(|capability| capability == tool.capability))
    .collect()
}

pub fn resolve_tool(name: &str) -> Option<&'static ToolDefinition> {
  all_tools().iter().find(|tool| tool.name == name)
}

pub fn input_schema(tool: &ToolDefinition) -> serde_json::Value {
  match tool.name {
    TOOL_LIST_LISTS => serde_json::json!({
      "type": "object",
      "properties": {}
    }),
    TOOL_LIST_REMINDERS => serde_json::json!({
      "type": "object",
      "properties": {
        "list_id": { "type": "string" }
      }
    }),
    TOOL_GET_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "reminder_id": { "type": "string" }
      },
      "required": ["reminder_id"]
    }),
    TOOL_SEARCH_REMINDERS => serde_json::json!({
      "type": "object",
      "properties": {
        "list_id": { "type": "string" },
        "completion_status": {
          "type": "string",
          "enum": ["incomplete", "completed", "all"]
        },
        "due_date_start": { "type": "string", "format": "date-time" },
        "due_date_end": { "type": "string", "format": "date-time" },
        "query": { "type": "string" }
      }
    }),
    _ => serde_json::json!({ "type": "object" }),
  }
}

#[cfg(test)]
mod tests {
  use super::{TOOL_GET_REMINDER, TOOL_LIST_LISTS, TOOL_LIST_REMINDERS, TOOL_SEARCH_REMINDERS, tools_for_capabilities};

  #[test]
  fn lists_read_tools_when_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_LIST_LISTS, TOOL_LIST_REMINDERS, TOOL_GET_REMINDER]);
  }

  #[test]
  fn lists_no_tools_when_capability_empty() {
    assert!(tools_for_capabilities(&[]).is_empty());
  }

  #[test]
  fn lists_search_tool_when_search_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.search".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SEARCH_REMINDERS]);
  }
}

//! MCP tool registry — name, capability, provider dispatch.

use crate::capabilities;

pub const TOOL_LIST_LISTS: &str = "eventkit.reminders.list_lists";
pub const TOOL_LIST_REMINDERS: &str = "eventkit.reminders.list_reminders";
pub const TOOL_GET_REMINDER: &str = "eventkit.reminders.get_reminder";
pub const TOOL_SEARCH_REMINDERS: &str = "eventkit.reminders.search_reminders";
pub const TOOL_CREATE_REMINDER: &str = "eventkit.reminders.create_reminder";
pub const TOOL_CREATE_LIST: &str = "eventkit.reminders.create_list";
pub const TOOL_UPDATE_REMINDER: &str = "eventkit.reminders.update_reminder";
pub const TOOL_MOVE_REMINDER: &str = "eventkit.reminders.move_reminder";
pub const TOOL_COMPLETE_REMINDER: &str = "eventkit.reminders.complete_reminder";
pub const TOOL_UNCOMPLETE_REMINDER: &str = "eventkit.reminders.uncomplete_reminder";
pub const TOOL_SET_REMINDER_ALARMS: &str = "eventkit.reminders.set_reminder_alarms";
pub const TOOL_SET_REMINDER_RECURRENCE: &str = "eventkit.reminders.set_reminder_recurrence";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ToolDefinition {
  pub name: &'static str,
  pub capability: &'static str,
  pub provider: &'static str,
  pub operation: &'static str,
  pub description: &'static str,
}

const ALL_TOOLS: [ToolDefinition; 12] = [
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
    description: "Search reminders with completion, due-date, and calendar filters",
  },
  ToolDefinition {
    name: TOOL_CREATE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_CREATE,
    provider: "eventkit",
    operation: "create_reminder",
    description: "Create a reminder in the given calendar with optional EventKit fields",
  },
  ToolDefinition {
    name: TOOL_CREATE_LIST,
    capability: capabilities::EVENTKIT_REMINDERS_CREATE,
    provider: "eventkit",
    operation: "create_list",
    description: "Create a reminder list with optional color and source",
  },
  ToolDefinition {
    name: TOOL_UPDATE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_EDIT,
    provider: "eventkit",
    operation: "update_reminder",
    description: "Update an existing reminder by reminder_id with optional EventKit fields",
  },
  ToolDefinition {
    name: TOOL_MOVE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_EDIT,
    provider: "eventkit",
    operation: "move_reminder",
    description: "Move a reminder to another list by reminder_id and target calendar_identifier",
  },
  ToolDefinition {
    name: TOOL_COMPLETE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_COMPLETE,
    provider: "eventkit",
    operation: "complete_reminder",
    description: "Mark a reminder as completed by reminder_id",
  },
  ToolDefinition {
    name: TOOL_UNCOMPLETE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_COMPLETE,
    provider: "eventkit",
    operation: "uncomplete_reminder",
    description: "Mark a reminder as incomplete by reminder_id",
  },
  ToolDefinition {
    name: TOOL_SET_REMINDER_ALARMS,
    capability: capabilities::EVENTKIT_REMINDERS_ALARMS,
    provider: "eventkit",
    operation: "set_reminder_alarms",
    description: "Replace a reminder's alarms by reminder_id; pass an empty array to remove all",
  },
  ToolDefinition {
    name: TOOL_SET_REMINDER_RECURRENCE,
    capability: capabilities::EVENTKIT_REMINDERS_RECURRENCE,
    provider: "eventkit",
    operation: "set_reminder_recurrence",
    description: "Replace a reminder's recurrence rules by reminder_id; pass an empty array to remove all",
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
        "calendar_identifier": { "type": "string" },
        "completion_status": {
          "type": "string",
          "enum": ["incomplete", "completed", "all"]
        },
        "due_date_start": { "type": "string", "format": "date-time" },
        "due_date_end": { "type": "string", "format": "date-time" }
      }
    }),
    TOOL_CREATE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_identifier": { "type": "string" },
        "title": { "type": "string" },
        "notes": { "type": "string" },
        "location": { "type": "string" },
        "url": { "type": "string" },
        "priority": { "type": "integer" },
        "due_date_components": { "type": "object" },
        "start_date_components": { "type": "object" },
        "time_zone": { "type": "string" },
        "is_completed": { "type": "boolean" },
        "completion_date": { "type": "string", "format": "date-time" },
        "alarms": { "type": "array" },
        "recurrence_rules": { "type": "array" }
      },
      "required": ["calendar_identifier", "title"]
    }),
    TOOL_CREATE_LIST => serde_json::json!({
      "type": "object",
      "properties": {
        "title": { "type": "string" },
        "cg_color": { "type": "object" },
        "source_identifier": { "type": "string" }
      },
      "required": ["title"]
    }),
    TOOL_UPDATE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "reminder_id": { "type": "string" },
        "calendar_identifier": { "type": "string" },
        "title": { "type": "string" },
        "notes": { "type": ["string", "null"] },
        "location": { "type": ["string", "null"] },
        "url": { "type": ["string", "null"] },
        "priority": { "type": "integer" },
        "due_date_components": { "type": ["object", "null"] },
        "start_date_components": { "type": ["object", "null"] },
        "time_zone": { "type": ["string", "null"] },
        "is_completed": { "type": "boolean" },
        "completion_date": { "type": ["string", "null"], "format": "date-time" },
        "alarms": { "type": ["array", "null"] },
        "recurrence_rules": { "type": ["array", "null"] }
      },
      "required": ["reminder_id"]
    }),
    TOOL_MOVE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "reminder_id": { "type": "string" },
        "calendar_identifier": { "type": "string" }
      },
      "required": ["reminder_id", "calendar_identifier"]
    }),
    TOOL_COMPLETE_REMINDER | TOOL_UNCOMPLETE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "reminder_id": { "type": "string" }
      },
      "required": ["reminder_id"]
    }),
    TOOL_SET_REMINDER_ALARMS => serde_json::json!({
      "type": "object",
      "properties": {
        "reminder_id": { "type": "string" },
        "alarms": { "type": "array" }
      },
      "required": ["reminder_id", "alarms"]
    }),
    TOOL_SET_REMINDER_RECURRENCE => serde_json::json!({
      "type": "object",
      "properties": {
        "reminder_id": { "type": "string" },
        "recurrence_rules": { "type": "array" }
      },
      "required": ["reminder_id", "recurrence_rules"]
    }),
    _ => serde_json::json!({ "type": "object" }),
  }
}

#[cfg(test)]
mod tests {
  use super::{
    TOOL_COMPLETE_REMINDER, TOOL_CREATE_LIST, TOOL_CREATE_REMINDER, TOOL_GET_REMINDER, TOOL_LIST_LISTS,
    TOOL_LIST_REMINDERS, TOOL_MOVE_REMINDER, TOOL_SEARCH_REMINDERS, TOOL_SET_REMINDER_ALARMS,
    TOOL_SET_REMINDER_RECURRENCE, TOOL_UNCOMPLETE_REMINDER, TOOL_UPDATE_REMINDER, tools_for_capabilities,
  };

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

  #[test]
  fn lists_create_tools_when_create_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.create".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_CREATE_REMINDER, TOOL_CREATE_LIST]);
  }

  #[test]
  fn lists_edit_tools_when_edit_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.edit".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_UPDATE_REMINDER, TOOL_MOVE_REMINDER]);
  }

  #[test]
  fn lists_complete_tools_when_complete_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.complete".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_COMPLETE_REMINDER, TOOL_UNCOMPLETE_REMINDER]);
  }

  #[test]
  fn lists_alarms_tool_when_alarms_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.alarms".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SET_REMINDER_ALARMS]);
  }

  #[test]
  fn lists_recurrence_tool_when_recurrence_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.recurrence".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SET_REMINDER_RECURRENCE]);
  }
}

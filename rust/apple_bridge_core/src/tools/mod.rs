//! MCP tool registry — name, capability, provider dispatch.

use crate::capabilities;

pub const TOOL_LIST_CALENDARS: &str = "eventkit.calendars.list_calendars";
pub const TOOL_CREATE_CALENDAR: &str = "eventkit.calendars.create_calendar";
pub const TOOL_UPDATE_CALENDAR: &str = "eventkit.calendars.update_calendar";
pub const TOOL_DELETE_CALENDAR: &str = "eventkit.calendars.delete_calendar";
pub const TOOL_LIST_EVENTS: &str = "eventkit.events.list_events";
pub const TOOL_GET_EVENT: &str = "eventkit.events.get_event";
pub const TOOL_SEARCH_EVENTS: &str = "eventkit.events.search_events";
pub const TOOL_CREATE_EVENT: &str = "eventkit.events.create_event";
pub const TOOL_UPDATE_EVENT: &str = "eventkit.events.update_event";
pub const TOOL_MOVE_EVENT: &str = "eventkit.events.move_event";
pub const TOOL_DELETE_EVENT: &str = "eventkit.events.delete_event";
pub const TOOL_LIST_LISTS: &str = "eventkit.reminders.list_lists";
pub const TOOL_LIST_REMINDERS: &str = "eventkit.reminders.list_reminders";
pub const TOOL_GET_REMINDER: &str = "eventkit.reminders.get_reminder";
pub const TOOL_SEARCH_REMINDERS: &str = "eventkit.reminders.search_reminders";
pub const TOOL_CREATE_REMINDER: &str = "eventkit.reminders.create_reminder";
pub const TOOL_CREATE_LIST: &str = "eventkit.reminders.create_list";
pub const TOOL_UPDATE_REMINDER: &str = "eventkit.reminders.update_reminder";
pub const TOOL_MOVE_REMINDER: &str = "eventkit.reminders.move_reminder";
pub const TOOL_DELETE_REMINDER: &str = "eventkit.reminders.delete_reminder";
pub const TOOL_DELETE_LIST: &str = "eventkit.reminders.delete_list";
pub const TOOL_COMPLETE_REMINDER: &str = "eventkit.reminders.complete_reminder";
pub const TOOL_UNCOMPLETE_REMINDER: &str = "eventkit.reminders.uncomplete_reminder";
pub const TOOL_SET_REMINDER_ALARMS: &str = "eventkit.reminders.set_reminder_alarms";
pub const TOOL_SET_EVENT_ALARMS: &str = "eventkit.events.set_event_alarms";
pub const TOOL_SET_REMINDER_RECURRENCE: &str = "eventkit.reminders.set_reminder_recurrence";
pub const TOOL_SET_EVENT_RECURRENCE: &str = "eventkit.events.set_event_recurrence";
pub const TOOL_ACCEPT_INVITATION: &str = "eventkit.events.accept_invitation";
pub const TOOL_DECLINE_INVITATION: &str = "eventkit.events.decline_invitation";
pub const TOOL_TENTATIVE_INVITATION: &str = "eventkit.events.tentative_invitation";
pub const TOOL_LIST_CONTACTS: &str = "contacts.list_contacts";
pub const TOOL_GET_CONTACT: &str = "contacts.get_contact";
pub const TOOL_SEARCH_CONTACTS: &str = "contacts.search_contacts";
pub const TOOL_CREATE_CONTACT: &str = "contacts.create_contact";
pub const TOOL_GET_USAGE_LOG: &str = "diagnostics.get_usage_log";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ToolDefinition {
  pub name: &'static str,
  pub capability: &'static str,
  pub provider: &'static str,
  pub operation: &'static str,
  pub description: &'static str,
}

const ALL_TOOLS: [ToolDefinition; 35] = [
  ToolDefinition {
    name: TOOL_LIST_CALENDARS,
    capability: capabilities::EVENTKIT_CALENDARS_READ,
    provider: "eventkit",
    operation: "list_calendars",
    description: "List event calendars",
  },
  ToolDefinition {
    name: TOOL_CREATE_CALENDAR,
    capability: capabilities::EVENTKIT_CALENDARS_CREATE,
    provider: "eventkit",
    operation: "create_calendar",
    description: "Create an event calendar with optional color and source",
  },
  ToolDefinition {
    name: TOOL_UPDATE_CALENDAR,
    capability: capabilities::EVENTKIT_CALENDARS_EDIT,
    provider: "eventkit",
    operation: "update_calendar",
    description: "Update an event calendar by calendar_identifier with optional title, color, and source",
  },
  ToolDefinition {
    name: TOOL_DELETE_CALENDAR,
    capability: capabilities::EVENTKIT_CALENDARS_DELETE,
    provider: "eventkit",
    operation: "delete_calendar",
    description: "Delete an event calendar by calendar_identifier",
  },
  ToolDefinition {
    name: TOOL_LIST_EVENTS,
    capability: capabilities::EVENTKIT_EVENTS_READ,
    provider: "eventkit",
    operation: "list_events",
    description: "List events in a date range, optionally filtered by calendar_identifier",
  },
  ToolDefinition {
    name: TOOL_GET_EVENT,
    capability: capabilities::EVENTKIT_EVENTS_READ,
    provider: "eventkit",
    operation: "get_event",
    description: "Get a single event by event_identifier",
  },
  ToolDefinition {
    name: TOOL_SEARCH_EVENTS,
    capability: capabilities::EVENTKIT_EVENTS_SEARCH,
    provider: "eventkit",
    operation: "search_events",
    description: "Search events with optional date range, calendar, and text query filters",
  },
  ToolDefinition {
    name: TOOL_CREATE_EVENT,
    capability: capabilities::EVENTKIT_EVENTS_CREATE,
    provider: "eventkit",
    operation: "create_event",
    description: "Create an event in the given calendar with optional EventKit fields",
  },
  ToolDefinition {
    name: TOOL_UPDATE_EVENT,
    capability: capabilities::EVENTKIT_EVENTS_EDIT,
    provider: "eventkit",
    operation: "update_event",
    description: "Update an existing event by event_identifier with optional EventKit fields",
  },
  ToolDefinition {
    name: TOOL_MOVE_EVENT,
    capability: capabilities::EVENTKIT_EVENTS_EDIT,
    provider: "eventkit",
    operation: "move_event",
    description: "Move an event to another calendar by event_identifier and target calendar_identifier",
  },
  ToolDefinition {
    name: TOOL_DELETE_EVENT,
    capability: capabilities::EVENTKIT_EVENTS_DELETE,
    provider: "eventkit",
    operation: "delete_event",
    description: "Delete an event by event_identifier",
  },
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
    name: TOOL_DELETE_REMINDER,
    capability: capabilities::EVENTKIT_REMINDERS_DELETE,
    provider: "eventkit",
    operation: "delete_reminder",
    description: "Delete a reminder by reminder_id",
  },
  ToolDefinition {
    name: TOOL_DELETE_LIST,
    capability: capabilities::EVENTKIT_REMINDERS_DELETE,
    provider: "eventkit",
    operation: "delete_list",
    description: "Delete a reminder list by calendar_identifier",
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
    name: TOOL_SET_EVENT_ALARMS,
    capability: capabilities::EVENTKIT_EVENTS_ALARMS,
    provider: "eventkit",
    operation: "set_event_alarms",
    description: "Replace an event's alarms by event_identifier; pass an empty array to remove all",
  },
  ToolDefinition {
    name: TOOL_SET_REMINDER_RECURRENCE,
    capability: capabilities::EVENTKIT_REMINDERS_RECURRENCE,
    provider: "eventkit",
    operation: "set_reminder_recurrence",
    description: "Replace a reminder's recurrence rules by reminder_id; pass an empty array to remove all",
  },
  ToolDefinition {
    name: TOOL_SET_EVENT_RECURRENCE,
    capability: capabilities::EVENTKIT_EVENTS_RECURRENCE,
    provider: "eventkit",
    operation: "set_event_recurrence",
    description: "Replace an event's recurrence rules by event_identifier; pass an empty array to remove all",
  },
  ToolDefinition {
    name: TOOL_ACCEPT_INVITATION,
    capability: capabilities::EVENTKIT_EVENTS_INVITATIONS,
    provider: "eventkit",
    operation: "accept_invitation",
    description: "Accept a calendar invitation for an event by event_identifier",
  },
  ToolDefinition {
    name: TOOL_DECLINE_INVITATION,
    capability: capabilities::EVENTKIT_EVENTS_INVITATIONS,
    provider: "eventkit",
    operation: "decline_invitation",
    description: "Decline a calendar invitation for an event by event_identifier",
  },
  ToolDefinition {
    name: TOOL_TENTATIVE_INVITATION,
    capability: capabilities::EVENTKIT_EVENTS_INVITATIONS,
    provider: "eventkit",
    operation: "tentative_invitation",
    description: "Mark a calendar invitation tentative for an event by event_identifier",
  },
  ToolDefinition {
    name: TOOL_LIST_CONTACTS,
    capability: capabilities::CONTACTS_READ,
    provider: "contacts",
    operation: "list_contacts",
    description: "List contacts, optionally filtered by container_identifier",
  },
  ToolDefinition {
    name: TOOL_GET_CONTACT,
    capability: capabilities::CONTACTS_READ,
    provider: "contacts",
    operation: "get_contact",
    description: "Get a single contact by contact_identifier",
  },
  ToolDefinition {
    name: TOOL_SEARCH_CONTACTS,
    capability: capabilities::CONTACTS_SEARCH,
    provider: "contacts",
    operation: "search_contacts",
    description: "Search contacts by name, email_address, and/or phone_number with optional container_identifier",
  },
  ToolDefinition {
    name: TOOL_CREATE_CONTACT,
    capability: capabilities::CONTACTS_CREATE,
    provider: "contacts",
    operation: "create_contact",
    description: "Create a contact in the given container with optional CNContact fields",
  },
  ToolDefinition {
    name: TOOL_GET_USAGE_LOG,
    capability: capabilities::DIAGNOSTICS_READ,
    provider: "diagnostics",
    operation: "get_usage_log",
    description: "Return the local usage audit log (read-only; no bearer tokens or payloads)",
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

fn nullable_string() -> serde_json::Value {
  serde_json::json!({ "type": ["string", "null"] })
}

fn non_whitespace_string() -> serde_json::Value {
  serde_json::json!({ "type": "string", "pattern": r".*\S.*" })
}

fn nullable_string_date_time() -> serde_json::Value {
  serde_json::json!({ "type": ["string", "null"], "format": "date-time" })
}

fn nullable_integer() -> serde_json::Value {
  serde_json::json!({ "type": ["integer", "null"] })
}

fn nullable_number() -> serde_json::Value {
  serde_json::json!({ "type": ["number", "null"] })
}

fn nullable_integer_array() -> serde_json::Value {
  serde_json::json!({
    "type": ["array", "null"],
    "items": { "type": "integer" }
  })
}

fn alarm_entry_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "object",
    "properties": {
      "absolute_date": nullable_string_date_time(),
      "relative_offset": nullable_number(),
      "proximity": {
        "type": ["string", "null"],
        "enum": ["none", "enter", "leave", null]
      },
      "email_address": nullable_string(),
      "structured_location": {
        "type": ["object", "null"],
        "properties": {
          "title": nullable_string(),
          "radius": nullable_number(),
          "geo_location": {
            "type": ["object", "null"],
            "properties": {
              "latitude": nullable_number(),
              "longitude": nullable_number()
            }
          }
        }
      }
    }
  })
}

fn alarms_array_schema(nullable: bool) -> serde_json::Value {
  if nullable {
    serde_json::json!({
      "type": ["array", "null"],
      "items": alarm_entry_schema()
    })
  } else {
    serde_json::json!({
      "type": "array",
      "items": alarm_entry_schema()
    })
  }
}

fn recurrence_rule_entry_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "object",
    "properties": {
      "frequency": {
        "type": "string",
        "enum": ["daily", "weekly", "monthly", "yearly"]
      },
      "interval": nullable_integer(),
      "recurrence_end": {
        "type": ["object", "null"],
        "properties": {
          "end_date": nullable_string_date_time(),
          "occurrence_count": nullable_integer()
        }
      },
      "days_of_the_week": {
        "type": ["array", "null"],
        "items": {
          "type": "object",
          "properties": {
            "day_of_the_week": { "type": "integer" },
            "week_number": nullable_integer()
          },
          "required": ["day_of_the_week"]
        }
      },
      "days_of_the_month": nullable_integer_array(),
      "days_of_the_year": nullable_integer_array(),
      "months_of_the_year": nullable_integer_array(),
      "weeks_of_the_year": nullable_integer_array(),
      "set_positions": nullable_integer_array()
    },
    "required": ["frequency"]
  })
}

fn structured_location_schema(nullable: bool) -> serde_json::Value {
  let schema = serde_json::json!({
    "type": "object",
    "properties": {
      "title": nullable_string(),
      "radius": nullable_number(),
      "geo_location": {
        "type": ["object", "null"],
        "properties": {
          "latitude": { "type": "number" },
          "longitude": { "type": "number" }
        },
        "required": ["latitude", "longitude"]
      }
    }
  });

  if nullable {
    serde_json::json!({
      "type": ["object", "null"],
      "properties": schema.get("properties").cloned().unwrap_or_default()
    })
  } else {
    schema
  }
}

fn recurrence_rules_array_schema(nullable: bool) -> serde_json::Value {
  if nullable {
    serde_json::json!({
      "type": ["array", "null"],
      "items": recurrence_rule_entry_schema()
    })
  } else {
    serde_json::json!({
      "type": "array",
      "items": recurrence_rule_entry_schema()
    })
  }
}

fn contact_date_components_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "object",
    "properties": {
      "era": nullable_integer(),
      "year": nullable_integer(),
      "month": nullable_integer(),
      "day": nullable_integer(),
      "hour": nullable_integer(),
      "minute": nullable_integer(),
      "second": nullable_integer(),
      "nanosecond": nullable_integer(),
      "weekday": nullable_integer(),
      "weekday_ordinal": nullable_integer(),
      "quarter": nullable_integer(),
      "week_of_month": nullable_integer(),
      "week_of_year": nullable_integer(),
      "year_for_week_of_year": nullable_integer(),
      "is_leap_month": { "type": ["boolean", "null"] },
      "time_zone": nullable_string(),
      "calendar": {
        "type": ["object", "null"],
        "properties": {
          "identifier": nullable_string(),
          "locale": nullable_string(),
          "time_zone": nullable_string(),
          "first_weekday": nullable_integer(),
          "minimum_days_in_first_week": nullable_integer()
        }
      }
    }
  })
}

fn contact_labeled_value_schema(value_schema: serde_json::Value) -> serde_json::Value {
  serde_json::json!({
    "type": "object",
    "properties": {
      "label": nullable_string(),
      "value": value_schema
    },
    "required": ["value"]
  })
}

fn contact_phone_numbers_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({
      "type": "object",
      "properties": {
        "string_value": { "type": "string" }
      },
      "required": ["string_value"]
    }))
  })
}

fn contact_postal_addresses_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({
      "type": "object",
      "properties": {
        "street": { "type": "string" },
        "sub_locality": { "type": "string" },
        "city": { "type": "string" },
        "sub_administrative_area": { "type": "string" },
        "state": { "type": "string" },
        "postal_code": { "type": "string" },
        "country": { "type": "string" },
        "iso_country_code": { "type": "string" }
      }
    }))
  })
}

fn contact_string_labeled_values_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({ "type": "string" }))
  })
}

fn contact_relations_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({
      "type": "object",
      "properties": {
        "name": { "type": "string" }
      },
      "required": ["name"]
    }))
  })
}

fn contact_social_profiles_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({
      "type": "object",
      "properties": {
        "url_string": nullable_string(),
        "username": nullable_string(),
        "user_identifier": nullable_string(),
        "service": nullable_string()
      }
    }))
  })
}

fn contact_instant_message_addresses_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(serde_json::json!({
      "type": "object",
      "properties": {
        "username": { "type": "string" },
        "service": { "type": "string" }
      },
      "required": ["username", "service"]
    }))
  })
}

fn contact_dates_schema() -> serde_json::Value {
  serde_json::json!({
    "type": "array",
    "items": contact_labeled_value_schema(contact_date_components_schema())
  })
}

pub fn input_schema(tool: &ToolDefinition) -> serde_json::Value {
  match tool.name {
    TOOL_LIST_CALENDARS | TOOL_LIST_LISTS => serde_json::json!({
      "type": "object",
      "properties": {}
    }),
    TOOL_LIST_EVENTS => serde_json::json!({
      "type": "object",
      "properties": {
        "start_date": { "type": "string", "format": "date-time" },
        "end_date": { "type": "string", "format": "date-time" },
        "calendar_identifier": { "type": "string" }
      },
      "required": ["start_date", "end_date"]
    }),
    TOOL_GET_EVENT => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": { "type": "string" }
      },
      "required": ["event_identifier"]
    }),
    TOOL_SEARCH_EVENTS => serde_json::json!({
      "type": "object",
      "properties": {
        "start_date": { "type": "string", "format": "date-time" },
        "end_date": { "type": "string", "format": "date-time" },
        "calendar_identifier": { "type": "string" },
        "query": { "type": "string" }
      },
      "required": ["query"]
    }),
    TOOL_CREATE_EVENT => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_identifier": { "type": "string" },
        "title": { "type": "string" },
        "notes": { "type": "string" },
        "location": { "type": "string" },
        "url": { "type": "string" },
        "time_zone": { "type": "string" },
        "start_date": { "type": "string", "format": "date-time" },
        "end_date": { "type": "string", "format": "date-time" },
        "is_all_day": { "type": "boolean" },
        "availability": {
          "type": "string",
          "enum": ["not_supported", "busy", "free", "tentative", "unavailable"]
        },
        "structured_location": structured_location_schema(true),
        "alarms": alarms_array_schema(false),
        "recurrence_rules": recurrence_rules_array_schema(false)
      },
      "required": ["calendar_identifier", "title", "start_date", "end_date"]
    }),
    TOOL_DELETE_EVENT | TOOL_ACCEPT_INVITATION | TOOL_DECLINE_INVITATION | TOOL_TENTATIVE_INVITATION => {
      serde_json::json!({
        "type": "object",
        "properties": {
          "event_identifier": { "type": "string" }
        },
        "required": ["event_identifier"]
      })
    }
    TOOL_MOVE_EVENT => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": { "type": "string" },
        "calendar_identifier": { "type": "string" }
      },
      "required": ["event_identifier", "calendar_identifier"]
    }),
    TOOL_UPDATE_EVENT => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": { "type": "string" },
        "calendar_identifier": { "type": "string" },
        "title": { "type": "string" },
        "notes": { "type": ["string", "null"] },
        "location": { "type": ["string", "null"] },
        "url": { "type": ["string", "null"] },
        "time_zone": { "type": ["string", "null"] },
        "start_date": { "type": "string", "format": "date-time" },
        "end_date": { "type": "string", "format": "date-time" },
        "is_all_day": { "type": "boolean" },
        "availability": {
          "type": ["string", "null"],
          "enum": ["not_supported", "busy", "free", "tentative", "unavailable", null]
        },
        "structured_location": structured_location_schema(true),
        "alarms": alarms_array_schema(true),
        "recurrence_rules": recurrence_rules_array_schema(true)
      },
      "required": ["event_identifier"]
    }),
    TOOL_CREATE_CALENDAR | TOOL_CREATE_LIST => serde_json::json!({
      "type": "object",
      "properties": {
        "title": { "type": "string" },
        "cg_color": { "type": "object" },
        "source_identifier": { "type": "string" }
      },
      "required": ["title"]
    }),
    TOOL_UPDATE_CALENDAR => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_identifier": { "type": "string" },
        "title": { "type": "string" },
        "cg_color": { "type": ["object", "null"] },
        "source_identifier": { "type": "string" }
      },
      "required": ["calendar_identifier"]
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
        "alarms": alarms_array_schema(false),
        "recurrence_rules": recurrence_rules_array_schema(false)
      },
      "required": ["calendar_identifier", "title"]
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
        "alarms": alarms_array_schema(true),
        "recurrence_rules": recurrence_rules_array_schema(true)
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
    TOOL_DELETE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "reminder_id": { "type": "string" }
      },
      "required": ["reminder_id"]
    }),
    TOOL_DELETE_LIST | TOOL_DELETE_CALENDAR => serde_json::json!({
      "type": "object",
      "properties": {
        "calendar_identifier": { "type": "string" }
      },
      "required": ["calendar_identifier"]
    }),
    TOOL_COMPLETE_REMINDER | TOOL_UNCOMPLETE_REMINDER => serde_json::json!({
      "type": "object",
      "properties": {
        "reminder_id": { "type": "string" }
      },
      "required": ["reminder_id"]
    }),
    TOOL_LIST_CONTACTS => serde_json::json!({
      "type": "object",
      "properties": {
        "container_identifier": { "type": "string" }
      }
    }),
    TOOL_GET_CONTACT => serde_json::json!({
      "type": "object",
      "properties": {
        "contact_identifier": { "type": "string" }
      },
      "required": ["contact_identifier"]
    }),
    TOOL_SEARCH_CONTACTS => serde_json::json!({
      "type": "object",
      "properties": {
        "name": { "type": "string", "minLength": 1 },
        "email_address": { "type": "string", "minLength": 1 },
        "phone_number": { "type": "string", "minLength": 1 },
        "container_identifier": { "type": "string" }
      },
      "anyOf": [
        { "required": ["name"] },
        { "required": ["email_address"] },
        { "required": ["phone_number"] }
      ]
    }),
    TOOL_CREATE_CONTACT => serde_json::json!({
      "type": "object",
      "properties": {
        "container_identifier": non_whitespace_string(),
        "contact_type": {
          "type": "string",
          "enum": ["person", "organization"]
        },
        "given_name": non_whitespace_string(),
        "family_name": non_whitespace_string(),
        "middle_name": { "type": "string" },
        "name_prefix": { "type": "string" },
        "name_suffix": { "type": "string" },
        "nickname": { "type": "string" },
        "organization_name": non_whitespace_string(),
        "department_name": { "type": "string" },
        "job_title": { "type": "string" },
        "phonetic_given_name": { "type": "string" },
        "phonetic_middle_name": { "type": "string" },
        "phonetic_family_name": { "type": "string" },
        "phonetic_organization_name": { "type": "string" },
        "previous_family_name": { "type": "string" },
        "note": { "type": "string" },
        "image_data": { "type": "string" },
        "birthday": contact_date_components_schema(),
        "non_gregorian_birthday": contact_date_components_schema(),
        "phone_numbers": contact_phone_numbers_schema(),
        "email_addresses": contact_string_labeled_values_schema(),
        "postal_addresses": contact_postal_addresses_schema(),
        "url_addresses": contact_string_labeled_values_schema(),
        "contact_relations": contact_relations_schema(),
        "social_profiles": contact_social_profiles_schema(),
        "instant_message_addresses": contact_instant_message_addresses_schema(),
        "dates": contact_dates_schema()
      },
      "required": ["container_identifier"],
      "anyOf": [
        { "required": ["given_name"] },
        { "required": ["family_name"] },
        { "required": ["organization_name"] }
      ]
    }),
    TOOL_GET_USAGE_LOG => serde_json::json!({
      "type": "object",
      "properties": {
        "limit": { "type": "integer", "minimum": 0 }
      }
    }),
    TOOL_SET_REMINDER_ALARMS => serde_json::json!({
      "type": "object",
      "properties": {
        "reminder_id": { "type": "string" },
        "alarms": alarms_array_schema(false)
      },
      "required": ["reminder_id", "alarms"]
    }),
    TOOL_SET_EVENT_ALARMS => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": { "type": "string" },
        "alarms": alarms_array_schema(false)
      },
      "required": ["event_identifier", "alarms"]
    }),
    TOOL_SET_REMINDER_RECURRENCE => serde_json::json!({
      "type": "object",
      "properties": {
        "reminder_id": { "type": "string" },
        "recurrence_rules": recurrence_rules_array_schema(false)
      },
      "required": ["reminder_id", "recurrence_rules"]
    }),
    TOOL_SET_EVENT_RECURRENCE => serde_json::json!({
      "type": "object",
      "properties": {
        "event_identifier": { "type": "string" },
        "recurrence_rules": recurrence_rules_array_schema(false)
      },
      "required": ["event_identifier", "recurrence_rules"]
    }),
    _ => serde_json::json!({ "type": "object" }),
  }
}

#[cfg(test)]
mod tests {
  use super::{
    TOOL_ACCEPT_INVITATION, TOOL_COMPLETE_REMINDER, TOOL_CREATE_CALENDAR, TOOL_CREATE_CONTACT, TOOL_CREATE_EVENT,
    TOOL_CREATE_LIST, TOOL_CREATE_REMINDER, TOOL_DECLINE_INVITATION, TOOL_DELETE_CALENDAR, TOOL_DELETE_EVENT,
    TOOL_DELETE_LIST, TOOL_DELETE_REMINDER, TOOL_GET_CONTACT, TOOL_GET_EVENT, TOOL_GET_REMINDER, TOOL_GET_USAGE_LOG,
    TOOL_LIST_CALENDARS, TOOL_LIST_CONTACTS, TOOL_LIST_EVENTS, TOOL_LIST_LISTS, TOOL_LIST_REMINDERS, TOOL_MOVE_EVENT,
    TOOL_MOVE_REMINDER, TOOL_SEARCH_CONTACTS, TOOL_SEARCH_EVENTS, TOOL_SEARCH_REMINDERS, TOOL_SET_EVENT_ALARMS,
    TOOL_SET_EVENT_RECURRENCE, TOOL_SET_REMINDER_ALARMS, TOOL_SET_REMINDER_RECURRENCE, TOOL_TENTATIVE_INVITATION,
    TOOL_UNCOMPLETE_REMINDER, TOOL_UPDATE_CALENDAR, TOOL_UPDATE_EVENT, TOOL_UPDATE_REMINDER, all_tools, input_schema,
    tools_for_capabilities,
  };

  fn array_items_type(schema: &serde_json::Value, property: &str) -> Option<String> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("items"))
      .and_then(|items| items.get("type"))
      .and_then(|value| value.as_str())
      .map(str::to_owned)
  }

  fn array_item_properties(
    schema: &serde_json::Value,
    property: &str,
  ) -> Option<serde_json::Map<String, serde_json::Value>> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("items"))
      .and_then(|items| items.get("properties"))
      .and_then(|value| value.as_object())
      .cloned()
  }

  #[test]
  fn set_reminder_alarms_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SET_REMINDER_ALARMS)
      .expect("set_reminder_alarms tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
  }

  #[test]
  fn set_event_alarms_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SET_EVENT_ALARMS)
      .expect("set_event_alarms tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
  }

  #[test]
  fn set_reminder_recurrence_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SET_REMINDER_RECURRENCE)
      .expect("set_reminder_recurrence tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn set_event_recurrence_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SET_EVENT_RECURRENCE)
      .expect("set_event_recurrence tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn create_reminder_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_CREATE_REMINDER)
      .expect("create_reminder tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn update_reminder_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_UPDATE_REMINDER)
      .expect("update_reminder tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn lists_create_calendar_tool_when_calendars_create_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.calendars.create".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_CREATE_CALENDAR]);
  }

  #[test]
  fn lists_update_calendar_tool_when_calendars_edit_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.calendars.edit".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_UPDATE_CALENDAR]);
  }

  #[test]
  fn lists_delete_calendar_tool_when_calendars_delete_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.calendars.delete".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_DELETE_CALENDAR]);
  }

  #[test]
  fn lists_events_tool_when_events_read_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_LIST_EVENTS, TOOL_GET_EVENT]);
  }

  #[test]
  fn lists_search_events_tool_when_events_search_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.search".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SEARCH_EVENTS]);
  }

  #[test]
  fn lists_create_event_tool_when_events_create_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.create".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_CREATE_EVENT]);
  }

  #[test]
  fn create_event_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_CREATE_EVENT)
      .expect("create_event tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn lists_update_event_tool_when_events_edit_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.edit".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_UPDATE_EVENT, TOOL_MOVE_EVENT]);
  }

  #[test]
  fn lists_delete_event_tool_when_events_delete_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.delete".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_DELETE_EVENT]);
  }

  #[test]
  fn update_event_schema_describes_object_array_items() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_UPDATE_EVENT)
      .expect("update_event tool");
    let schema = input_schema(tool);

    assert_eq!(array_items_type(&schema, "alarms").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "recurrence_rules").as_deref(), Some("object"));
  }

  #[test]
  fn lists_calendars_tool_when_calendars_read_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.calendars.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_LIST_CALENDARS]);
  }

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
  fn lists_delete_tools_when_delete_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.delete".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_DELETE_REMINDER, TOOL_DELETE_LIST]);
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
  fn lists_event_alarms_tool_when_events_alarms_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.alarms".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SET_EVENT_ALARMS]);
  }

  #[test]
  fn lists_recurrence_tool_when_recurrence_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.reminders.recurrence".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SET_REMINDER_RECURRENCE]);
  }

  #[test]
  fn lists_event_recurrence_tool_when_events_recurrence_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.recurrence".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SET_EVENT_RECURRENCE]);
  }

  #[test]
  fn lists_invitation_tools_when_events_invitations_capability_enabled() {
    let tools = tools_for_capabilities(&["eventkit.events.invitations".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(
      names,
      vec![
        TOOL_ACCEPT_INVITATION,
        TOOL_DECLINE_INVITATION,
        TOOL_TENTATIVE_INVITATION
      ]
    );
  }

  #[test]
  fn lists_contacts_tool_when_contacts_read_capability_enabled() {
    let tools = tools_for_capabilities(&["contacts.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_LIST_CONTACTS, TOOL_GET_CONTACT]);
  }

  #[test]
  fn get_contact_schema_requires_contact_identifier() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_GET_CONTACT)
      .expect("get_contact tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["contact_identifier".to_owned()])
    );
  }

  #[test]
  fn lists_search_contacts_tool_when_contacts_search_capability_enabled() {
    let tools = tools_for_capabilities(&["contacts.search".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_SEARCH_CONTACTS]);
  }

  #[test]
  fn lists_create_contact_tool_when_contacts_create_capability_enabled() {
    let tools = tools_for_capabilities(&["contacts.create".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_CREATE_CONTACT]);
  }

  #[test]
  fn create_contact_schema_requires_container_identifier_and_name_field() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_CREATE_CONTACT)
      .expect("create_contact tool");
    let schema = input_schema(tool);

    assert_eq!(
      schema.get("required").and_then(|value| value.as_array()).map(|fields| {
        fields
          .iter()
          .filter_map(|field| field.as_str().map(str::to_owned))
          .collect::<Vec<_>>()
      }),
      Some(vec!["container_identifier".to_owned()])
    );
    assert_eq!(
      any_of_required_fields(&schema),
      vec![
        vec!["given_name".to_owned()],
        vec!["family_name".to_owned()],
        vec!["organization_name".to_owned()]
      ]
    );
    assert_eq!(
      string_property_pattern(&schema, "container_identifier").as_deref(),
      Some(r".*\S.*")
    );
    assert_eq!(
      string_property_pattern(&schema, "given_name").as_deref(),
      Some(r".*\S.*")
    );
    assert_eq!(
      string_property_pattern(&schema, "family_name").as_deref(),
      Some(r".*\S.*")
    );
    assert_eq!(
      string_property_pattern(&schema, "organization_name").as_deref(),
      Some(r".*\S.*")
    );
    assert_eq!(array_items_type(&schema, "phone_numbers").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "postal_addresses").as_deref(), Some("object"));
    assert_eq!(array_items_type(&schema, "dates").as_deref(), Some("object"));
    let properties = schema
      .get("properties")
      .and_then(|value| value.as_object())
      .expect("create_contact properties");
    assert!(properties.contains_key("image_data"));
    assert!(!properties.contains_key("thumbnail_image_data"));
    for property in [
      "phone_numbers",
      "email_addresses",
      "postal_addresses",
      "url_addresses",
      "contact_relations",
      "social_profiles",
      "instant_message_addresses",
      "dates",
    ] {
      let item_properties =
        array_item_properties(&schema, property).unwrap_or_else(|| panic!("{property} labeled-value item properties"));
      assert!(
        !item_properties.contains_key("identifier"),
        "{property} must not advertise labeled-value identifier on create"
      );
      assert!(item_properties.contains_key("label"));
      assert!(item_properties.contains_key("value"));
    }
  }

  fn string_property_min_length(schema: &serde_json::Value, property: &str) -> Option<u64> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("minLength"))
      .and_then(|value| value.as_u64())
  }

  fn string_property_pattern(schema: &serde_json::Value, property: &str) -> Option<String> {
    schema
      .get("properties")
      .and_then(|properties| properties.get(property))
      .and_then(|property_schema| property_schema.get("pattern"))
      .and_then(|value| value.as_str())
      .map(str::to_owned)
  }

  fn any_of_required_fields(schema: &serde_json::Value) -> Vec<Vec<String>> {
    schema
      .get("anyOf")
      .and_then(|value| value.as_array())
      .map(|constraints| {
        constraints
          .iter()
          .filter_map(|constraint| {
            constraint
              .get("required")
              .and_then(|required| required.as_array())
              .map(|fields| {
                fields
                  .iter()
                  .filter_map(|field| field.as_str().map(str::to_owned))
                  .collect()
              })
          })
          .collect()
      })
      .unwrap_or_default()
  }

  #[test]
  fn search_contacts_schema_requires_non_empty_search_strings() {
    let tool = all_tools()
      .iter()
      .find(|tool| tool.name == TOOL_SEARCH_CONTACTS)
      .expect("search_contacts tool");
    let schema = input_schema(tool);

    assert_eq!(string_property_min_length(&schema, "name"), Some(1));
    assert_eq!(string_property_min_length(&schema, "email_address"), Some(1));
    assert_eq!(string_property_min_length(&schema, "phone_number"), Some(1));
    assert_eq!(
      any_of_required_fields(&schema),
      vec![
        vec!["name".to_owned()],
        vec!["email_address".to_owned()],
        vec!["phone_number".to_owned()]
      ]
    );
  }

  #[test]
  fn lists_diagnostics_tool_when_diagnostics_read_capability_enabled() {
    let tools = tools_for_capabilities(&["diagnostics.read".into()]);
    let names: Vec<_> = tools.iter().map(|tool| tool.name).collect();
    assert_eq!(names, vec![TOOL_GET_USAGE_LOG]);
  }
}

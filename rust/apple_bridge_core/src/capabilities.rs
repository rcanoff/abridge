//! Capability IDs for MCP tool gating (PR 3a allowlist).

pub const EVENTKIT_REMINDERS_READ: &str = "eventkit.reminders.read";
pub const EVENTKIT_REMINDERS_SEARCH: &str = "eventkit.reminders.search";
pub const EVENTKIT_REMINDERS_CREATE: &str = "eventkit.reminders.create";
pub const EVENTKIT_REMINDERS_EDIT: &str = "eventkit.reminders.edit";
pub const EVENTKIT_REMINDERS_DELETE: &str = "eventkit.reminders.delete";
pub const EVENTKIT_REMINDERS_COMPLETE: &str = "eventkit.reminders.complete";
pub const EVENTKIT_REMINDERS_ALARMS: &str = "eventkit.reminders.alarms";
pub const EVENTKIT_REMINDERS_RECURRENCE: &str = "eventkit.reminders.recurrence";
pub const EVENTKIT_CALENDARS_READ: &str = "eventkit.calendars.read";
pub const EVENTKIT_CALENDARS_CREATE: &str = "eventkit.calendars.create";
pub const EVENTKIT_CALENDARS_EDIT: &str = "eventkit.calendars.edit";
pub const EVENTKIT_CALENDARS_DELETE: &str = "eventkit.calendars.delete";
pub const EVENTKIT_EVENTS_READ: &str = "eventkit.events.read";
pub const EVENTKIT_EVENTS_SEARCH: &str = "eventkit.events.search";
pub const EVENTKIT_EVENTS_CREATE: &str = "eventkit.events.create";
pub const EVENTKIT_EVENTS_EDIT: &str = "eventkit.events.edit";
pub const DIAGNOSTICS_READ: &str = "diagnostics.read";

pub fn is_valid_capability_id(id: &str) -> bool {
  if id == DIAGNOSTICS_READ {
    return true;
  }

  !id.is_empty()
    && id == id.to_lowercase()
    && !id.chars().any(char::is_whitespace)
    && id.split('.').count() >= 3
    && id
      .split('.')
      .all(|segment| !segment.is_empty() && segment == segment.to_lowercase())
}

pub fn is_allowed_in_v1(id: &str) -> bool {
  matches!(
    id,
    EVENTKIT_REMINDERS_READ
      | EVENTKIT_REMINDERS_SEARCH
      | EVENTKIT_REMINDERS_CREATE
      | EVENTKIT_REMINDERS_EDIT
      | EVENTKIT_REMINDERS_DELETE
      | EVENTKIT_REMINDERS_COMPLETE
      | EVENTKIT_REMINDERS_ALARMS
      | EVENTKIT_REMINDERS_RECURRENCE
      | EVENTKIT_CALENDARS_READ
      | EVENTKIT_CALENDARS_CREATE
      | EVENTKIT_CALENDARS_EDIT
      | EVENTKIT_CALENDARS_DELETE
      | EVENTKIT_EVENTS_READ
      | EVENTKIT_EVENTS_SEARCH
      | EVENTKIT_EVENTS_CREATE
      | EVENTKIT_EVENTS_EDIT
      | DIAGNOSTICS_READ
  )
}

#[cfg(test)]
mod tests {
  use super::{
    DIAGNOSTICS_READ, EVENTKIT_CALENDARS_CREATE, EVENTKIT_CALENDARS_DELETE, EVENTKIT_CALENDARS_EDIT,
    EVENTKIT_CALENDARS_READ, EVENTKIT_EVENTS_CREATE, EVENTKIT_EVENTS_EDIT, EVENTKIT_EVENTS_READ,
    EVENTKIT_EVENTS_SEARCH, EVENTKIT_REMINDERS_ALARMS, EVENTKIT_REMINDERS_COMPLETE, EVENTKIT_REMINDERS_CREATE,
    EVENTKIT_REMINDERS_DELETE, EVENTKIT_REMINDERS_EDIT, EVENTKIT_REMINDERS_READ, EVENTKIT_REMINDERS_RECURRENCE,
    EVENTKIT_REMINDERS_SEARCH, is_allowed_in_v1, is_valid_capability_id,
  };

  #[test]
  fn accepts_read_capability_shape() {
    assert!(is_valid_capability_id(EVENTKIT_REMINDERS_READ));
  }

  #[test]
  fn accepts_diagnostics_read_capability_shape() {
    assert!(is_valid_capability_id(DIAGNOSTICS_READ));
  }

  #[test]
  fn rejects_uppercase_capability() {
    assert!(!is_valid_capability_id("EventKit.Reminders.Read"));
  }

  #[test]
  fn rejects_whitespace_padded_capability() {
    assert!(!is_valid_capability_id(" eventkit.reminders.read "));
  }

  #[test]
  fn v1_allowlist_includes_read_search_create_edit_delete_complete_alarms_recurrence_and_diagnostics() {
    assert!(is_allowed_in_v1(DIAGNOSTICS_READ));
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_READ));
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_SEARCH));
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_CREATE));
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_EDIT));
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_DELETE));
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_COMPLETE));
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_ALARMS));
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_RECURRENCE));
    assert!(is_allowed_in_v1(EVENTKIT_CALENDARS_READ));
    assert!(is_allowed_in_v1(EVENTKIT_CALENDARS_CREATE));
    assert!(is_allowed_in_v1(EVENTKIT_CALENDARS_EDIT));
    assert!(is_allowed_in_v1(EVENTKIT_CALENDARS_DELETE));
    assert!(is_allowed_in_v1(EVENTKIT_EVENTS_READ));
    assert!(is_allowed_in_v1(EVENTKIT_EVENTS_SEARCH));
    assert!(is_allowed_in_v1(EVENTKIT_EVENTS_CREATE));
    assert!(is_allowed_in_v1(EVENTKIT_EVENTS_EDIT));
    assert!(!is_allowed_in_v1("eventkit.reminders.write"));
  }
}

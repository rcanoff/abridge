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
pub const EVENTKIT_EVENTS_DELETE: &str = "eventkit.events.delete";
pub const EVENTKIT_EVENTS_ALARMS: &str = "eventkit.events.alarms";
pub const EVENTKIT_EVENTS_RECURRENCE: &str = "eventkit.events.recurrence";
pub const EVENTKIT_EVENTS_INVITATIONS: &str = "eventkit.events.invitations";
pub const CONTACTS_READ: &str = "contacts.read";
pub const CONTACTS_SEARCH: &str = "contacts.search";
pub const CONTACTS_CREATE: &str = "contacts.create";
pub const CONTACTS_EDIT: &str = "contacts.edit";
pub const CONTACTS_DELETE: &str = "contacts.delete";
pub const MAPKIT_SEARCH: &str = "mapkit.search";
pub const MAPKIT_GEOCODE: &str = "mapkit.geocode";
pub const MAPKIT_ROUTING: &str = "mapkit.routing";
pub const MAPKIT_READ: &str = "mapkit.read";
pub const DIAGNOSTICS_READ: &str = "diagnostics.read";

pub fn is_valid_capability_id(id: &str) -> bool {
  if id == CONTACTS_READ
    || id == CONTACTS_SEARCH
    || id == CONTACTS_CREATE
    || id == CONTACTS_EDIT
    || id == CONTACTS_DELETE
    || id == MAPKIT_SEARCH
    || id == MAPKIT_GEOCODE
    || id == MAPKIT_ROUTING
    || id == MAPKIT_READ
    || id == DIAGNOSTICS_READ
  {
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
      | EVENTKIT_EVENTS_DELETE
      | EVENTKIT_EVENTS_ALARMS
      | EVENTKIT_EVENTS_RECURRENCE
      | EVENTKIT_EVENTS_INVITATIONS
      | CONTACTS_READ
      | CONTACTS_SEARCH
      | CONTACTS_CREATE
      | CONTACTS_EDIT
      | CONTACTS_DELETE
      | MAPKIT_SEARCH
      | MAPKIT_GEOCODE
      | MAPKIT_ROUTING
      | MAPKIT_READ
      | DIAGNOSTICS_READ
  )
}

#[cfg(test)]
mod tests {
  use super::{
    CONTACTS_CREATE, CONTACTS_DELETE, CONTACTS_EDIT, CONTACTS_READ, CONTACTS_SEARCH, DIAGNOSTICS_READ,
    EVENTKIT_CALENDARS_CREATE, EVENTKIT_CALENDARS_DELETE, EVENTKIT_CALENDARS_EDIT, EVENTKIT_CALENDARS_READ,
    EVENTKIT_EVENTS_ALARMS, EVENTKIT_EVENTS_CREATE, EVENTKIT_EVENTS_DELETE, EVENTKIT_EVENTS_EDIT,
    EVENTKIT_EVENTS_INVITATIONS, EVENTKIT_EVENTS_READ, EVENTKIT_EVENTS_RECURRENCE, EVENTKIT_EVENTS_SEARCH,
    EVENTKIT_REMINDERS_ALARMS, EVENTKIT_REMINDERS_COMPLETE, EVENTKIT_REMINDERS_CREATE, EVENTKIT_REMINDERS_DELETE,
    EVENTKIT_REMINDERS_EDIT, EVENTKIT_REMINDERS_READ, EVENTKIT_REMINDERS_RECURRENCE, EVENTKIT_REMINDERS_SEARCH,
    MAPKIT_GEOCODE, MAPKIT_READ, MAPKIT_ROUTING, MAPKIT_SEARCH, is_allowed_in_v1, is_valid_capability_id,
  };

  #[test]
  fn accepts_read_capability_shape() {
    assert!(is_valid_capability_id(EVENTKIT_REMINDERS_READ));
  }

  #[test]
  fn accepts_contacts_read_capability_shape() {
    assert!(is_valid_capability_id(CONTACTS_READ));
  }

  #[test]
  fn accepts_contacts_search_capability_shape() {
    assert!(is_valid_capability_id(CONTACTS_SEARCH));
  }

  #[test]
  fn accepts_contacts_create_capability_shape() {
    assert!(is_valid_capability_id(CONTACTS_CREATE));
  }

  #[test]
  fn accepts_contacts_edit_capability_shape() {
    assert!(is_valid_capability_id(CONTACTS_EDIT));
  }

  #[test]
  fn accepts_contacts_delete_capability_shape() {
    assert!(is_valid_capability_id(CONTACTS_DELETE));
  }

  #[test]
  fn accepts_diagnostics_read_capability_shape() {
    assert!(is_valid_capability_id(DIAGNOSTICS_READ));
  }

  #[test]
  fn accepts_mapkit_search_capability_shape() {
    assert!(is_valid_capability_id(MAPKIT_SEARCH));
    assert!(is_allowed_in_v1(MAPKIT_SEARCH));
  }

  #[test]
  fn accepts_mapkit_geocode_capability_shape() {
    assert!(is_valid_capability_id(MAPKIT_GEOCODE));
    assert!(is_allowed_in_v1(MAPKIT_GEOCODE));
  }

  #[test]
  fn accepts_mapkit_routing_capability_shape() {
    assert!(is_valid_capability_id(MAPKIT_ROUTING));
    assert!(is_allowed_in_v1(MAPKIT_ROUTING));
  }

  #[test]
  fn accepts_mapkit_read_capability_shape() {
    assert!(is_valid_capability_id(MAPKIT_READ));
    assert!(is_allowed_in_v1(MAPKIT_READ));
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
    assert!(is_allowed_in_v1(EVENTKIT_EVENTS_DELETE));
    assert!(is_allowed_in_v1(EVENTKIT_EVENTS_ALARMS));
    assert!(is_allowed_in_v1(EVENTKIT_EVENTS_RECURRENCE));
    assert!(is_allowed_in_v1(EVENTKIT_EVENTS_INVITATIONS));
    assert!(is_allowed_in_v1(CONTACTS_READ));
    assert!(is_allowed_in_v1(CONTACTS_SEARCH));
    assert!(is_allowed_in_v1(CONTACTS_CREATE));
    assert!(is_allowed_in_v1(CONTACTS_EDIT));
    assert!(is_allowed_in_v1(CONTACTS_DELETE));
    assert!(is_allowed_in_v1(MAPKIT_SEARCH));
    assert!(!is_allowed_in_v1("eventkit.reminders.write"));
  }
}

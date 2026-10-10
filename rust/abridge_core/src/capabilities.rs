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
pub const MAPKIT_NAVIGATION: &str = "mapkit.navigation";
pub const CORELOCATION_READ: &str = "corelocation.read";
pub const DIAGNOSTICS_READ: &str = "diagnostics.read";
pub const VISION_TEXT: &str = "vision.text";
pub const VISION_DOCUMENT: &str = "vision.document";
pub const VISION_BARCODES: &str = "vision.barcodes";
pub const VISION_FACES: &str = "vision.faces";

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
    || id == MAPKIT_NAVIGATION
    || id == CORELOCATION_READ
    || id == DIAGNOSTICS_READ
    || id == VISION_TEXT
    || id == VISION_DOCUMENT
    || id == VISION_BARCODES
    || id == VISION_FACES
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
      | MAPKIT_NAVIGATION
      | CORELOCATION_READ
      | DIAGNOSTICS_READ
      | VISION_TEXT
      | VISION_DOCUMENT
      | VISION_BARCODES
      | VISION_FACES
  )
}

#[cfg(test)]
mod tests {
  use super::{
    CONTACTS_CREATE, CONTACTS_DELETE, CONTACTS_EDIT, CONTACTS_READ, CONTACTS_SEARCH, CORELOCATION_READ,
    DIAGNOSTICS_READ, EVENTKIT_CALENDARS_CREATE, EVENTKIT_CALENDARS_DELETE, EVENTKIT_CALENDARS_EDIT,
    EVENTKIT_CALENDARS_READ, EVENTKIT_EVENTS_ALARMS, EVENTKIT_EVENTS_CREATE, EVENTKIT_EVENTS_DELETE,
    EVENTKIT_EVENTS_EDIT, EVENTKIT_EVENTS_INVITATIONS, EVENTKIT_EVENTS_READ, EVENTKIT_EVENTS_RECURRENCE,
    EVENTKIT_EVENTS_SEARCH, EVENTKIT_REMINDERS_ALARMS, EVENTKIT_REMINDERS_COMPLETE, EVENTKIT_REMINDERS_CREATE,
    EVENTKIT_REMINDERS_DELETE, EVENTKIT_REMINDERS_EDIT, EVENTKIT_REMINDERS_READ, EVENTKIT_REMINDERS_RECURRENCE,
    EVENTKIT_REMINDERS_SEARCH, MAPKIT_GEOCODE, MAPKIT_NAVIGATION, MAPKIT_READ, MAPKIT_ROUTING, MAPKIT_SEARCH,
    VISION_BARCODES, VISION_DOCUMENT, VISION_FACES, VISION_TEXT, is_allowed_in_v1, is_valid_capability_id,
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
  fn accepts_corelocation_read_capability_shape() {
    assert!(is_valid_capability_id(CORELOCATION_READ));
    assert!(is_allowed_in_v1(CORELOCATION_READ));
  }

  #[test]
  fn accepts_mapkit_read_capability_shape() {
    assert!(is_valid_capability_id(MAPKIT_READ));
    assert!(is_allowed_in_v1(MAPKIT_READ));
  }

  #[test]
  fn accepts_mapkit_navigation_capability_shape() {
    assert!(is_valid_capability_id(MAPKIT_NAVIGATION));
    assert!(is_allowed_in_v1(MAPKIT_NAVIGATION));
  }

  #[test]
  fn accepts_vision_text_capability_shape() {
    assert!(is_valid_capability_id(VISION_TEXT));
    assert!(is_allowed_in_v1(VISION_TEXT));
  }

  #[test]
  fn accepts_vision_document_capability_shape() {
    assert!(is_valid_capability_id(VISION_DOCUMENT));
    assert!(is_allowed_in_v1(VISION_DOCUMENT));
  }

  #[test]
  fn accepts_vision_barcodes_capability_shape() {
    assert!(is_valid_capability_id(VISION_BARCODES));
    assert!(is_allowed_in_v1(VISION_BARCODES));
  }

  #[test]
  fn accepts_vision_faces_capability_shape() {
    assert!(is_valid_capability_id(VISION_FACES));
    assert!(is_allowed_in_v1(VISION_FACES));
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
    assert!(is_allowed_in_v1(CORELOCATION_READ));
    assert!(!is_allowed_in_v1("eventkit.reminders.write"));
  }
}

/// UI group for Settings capability rows (mirrors previous Swift sections).
pub const SETTINGS_GROUP_REMINDERS: &str = "reminders";
pub const SETTINGS_GROUP_CALENDARS: &str = "calendars";
pub const SETTINGS_GROUP_EVENTS: &str = "events";
pub const SETTINGS_GROUP_CONTACTS: &str = "contacts";
pub const SETTINGS_GROUP_MAPKIT: &str = "mapkit";
pub const SETTINGS_GROUP_CORELOCATION: &str = "corelocation";
pub const SETTINGS_GROUP_VISION: &str = "vision";

/// Settings catalog entry — single source of truth for capability IDs shown in the app.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct SettingsCapabilityDefinition {
  pub group: String,
  pub id: String,
  pub capability_id: String,
  pub label: String,
  pub shipped: bool,
}

fn settings_entry(
  group: &str,
  id: &str,
  capability_id: &str,
  label: &str,
  shipped: bool,
) -> SettingsCapabilityDefinition {
  SettingsCapabilityDefinition {
    group: group.to_owned(),
    id: id.to_owned(),
    capability_id: capability_id.to_owned(),
    label: label.to_owned(),
    shipped,
  }
}

/// Canonical Settings capability list. Labels/UI ids match historical Swift catalog.
pub fn settings_capability_catalog() -> Vec<SettingsCapabilityDefinition> {
  vec![
    // reminders
    settings_entry(SETTINGS_GROUP_REMINDERS, "read", EVENTKIT_REMINDERS_READ, "Read", true),
    settings_entry(
      SETTINGS_GROUP_REMINDERS,
      "create",
      EVENTKIT_REMINDERS_CREATE,
      "Create",
      true,
    ),
    settings_entry(SETTINGS_GROUP_REMINDERS, "edit", EVENTKIT_REMINDERS_EDIT, "Edit", true),
    settings_entry(
      SETTINGS_GROUP_REMINDERS,
      "delete",
      EVENTKIT_REMINDERS_DELETE,
      "Delete",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_REMINDERS,
      "complete",
      EVENTKIT_REMINDERS_COMPLETE,
      "Complete",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_REMINDERS,
      "alarms",
      EVENTKIT_REMINDERS_ALARMS,
      "Alarms",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_REMINDERS,
      "recurrence",
      EVENTKIT_REMINDERS_RECURRENCE,
      "Recurrence",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_REMINDERS,
      "search",
      EVENTKIT_REMINDERS_SEARCH,
      "Search",
      true,
    ),
    // calendars
    settings_entry(
      SETTINGS_GROUP_CALENDARS,
      "calendars-read",
      EVENTKIT_CALENDARS_READ,
      "Read",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_CALENDARS,
      "calendars-create",
      EVENTKIT_CALENDARS_CREATE,
      "Create",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_CALENDARS,
      "calendars-edit",
      EVENTKIT_CALENDARS_EDIT,
      "Edit",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_CALENDARS,
      "calendars-delete",
      EVENTKIT_CALENDARS_DELETE,
      "Delete",
      true,
    ),
    // events
    settings_entry(SETTINGS_GROUP_EVENTS, "events-read", EVENTKIT_EVENTS_READ, "Read", true),
    settings_entry(
      SETTINGS_GROUP_EVENTS,
      "events-search",
      EVENTKIT_EVENTS_SEARCH,
      "Search",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_EVENTS,
      "events-create",
      EVENTKIT_EVENTS_CREATE,
      "Create",
      true,
    ),
    settings_entry(SETTINGS_GROUP_EVENTS, "events-edit", EVENTKIT_EVENTS_EDIT, "Edit", true),
    settings_entry(
      SETTINGS_GROUP_EVENTS,
      "events-delete",
      EVENTKIT_EVENTS_DELETE,
      "Delete",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_EVENTS,
      "events-alarms",
      EVENTKIT_EVENTS_ALARMS,
      "Alarms",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_EVENTS,
      "events-recurrence",
      EVENTKIT_EVENTS_RECURRENCE,
      "Recurrence",
      true,
    ),
    // invitations: tools exist; Settings ships=false until live RSVP API
    settings_entry(
      SETTINGS_GROUP_EVENTS,
      "events-invitations",
      EVENTKIT_EVENTS_INVITATIONS,
      "Invitations",
      false,
    ),
    // contacts
    settings_entry(SETTINGS_GROUP_CONTACTS, "contacts-read", CONTACTS_READ, "Read", true),
    settings_entry(
      SETTINGS_GROUP_CONTACTS,
      "contacts-search",
      CONTACTS_SEARCH,
      "Search",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_CONTACTS,
      "contacts-create",
      CONTACTS_CREATE,
      "Create",
      true,
    ),
    settings_entry(SETTINGS_GROUP_CONTACTS, "contacts-edit", CONTACTS_EDIT, "Edit", true),
    settings_entry(
      SETTINGS_GROUP_CONTACTS,
      "contacts-delete",
      CONTACTS_DELETE,
      "Delete",
      true,
    ),
    // mapkit
    settings_entry(SETTINGS_GROUP_MAPKIT, "mapkit-search", MAPKIT_SEARCH, "Search", true),
    settings_entry(SETTINGS_GROUP_MAPKIT, "mapkit-geocode", MAPKIT_GEOCODE, "Geocode", true),
    settings_entry(SETTINGS_GROUP_MAPKIT, "mapkit-routing", MAPKIT_ROUTING, "Routing", true),
    settings_entry(
      SETTINGS_GROUP_MAPKIT,
      "mapkit-navigation",
      MAPKIT_NAVIGATION,
      "Navigation",
      true,
    ),
    settings_entry(SETTINGS_GROUP_MAPKIT, "mapkit-read", MAPKIT_READ, "Read", true),
    settings_entry(
      SETTINGS_GROUP_CORELOCATION,
      "corelocation-read",
      CORELOCATION_READ,
      "Current location",
      true,
    ),
    // vision
    settings_entry(SETTINGS_GROUP_VISION, "vision-text", VISION_TEXT, "Text", true),
    settings_entry(
      SETTINGS_GROUP_VISION,
      "vision-document",
      VISION_DOCUMENT,
      "Document",
      true,
    ),
    settings_entry(
      SETTINGS_GROUP_VISION,
      "vision-barcodes",
      VISION_BARCODES,
      "Barcodes",
      true,
    ),
    settings_entry(SETTINGS_GROUP_VISION, "vision-faces", VISION_FACES, "Faces", true),
  ]
}

/// UniFFI export: Settings consumes this list; do not hand-maintain a second ID table in Swift.
#[uniffi::export]
pub fn list_settings_capabilities() -> Vec<SettingsCapabilityDefinition> {
  settings_capability_catalog()
}

#[cfg(test)]
mod catalog_tests {
  use super::{
    EVENTKIT_EVENTS_INVITATIONS, EVENTKIT_REMINDERS_READ, SETTINGS_GROUP_REMINDERS, is_allowed_in_v1,
    list_settings_capabilities, settings_capability_catalog,
  };

  #[test]
  fn catalog_includes_reminders_read_with_label() {
    let entry = settings_capability_catalog()
      .into_iter()
      .find(|e| e.capability_id == EVENTKIT_REMINDERS_READ)
      .expect("reminders read");
    assert_eq!(entry.group, SETTINGS_GROUP_REMINDERS);
    assert_eq!(entry.id, "read");
    assert_eq!(entry.label, "Read");
    assert!(entry.shipped);
  }

  #[test]
  fn catalog_has_expected_count_and_unique_capability_ids() {
    let catalog = settings_capability_catalog();
    assert_eq!(catalog.len(), 35);
    let mut ids: Vec<_> = catalog.iter().map(|e| e.capability_id.clone()).collect();
    ids.sort();
    ids.dedup();
    assert_eq!(ids.len(), 35);
  }

  #[test]
  fn every_catalog_capability_is_allowed_in_v1() {
    for entry in settings_capability_catalog() {
      assert!(
        is_allowed_in_v1(&entry.capability_id),
        "not allowlisted: {}",
        entry.capability_id
      );
    }
  }

  #[test]
  fn invitations_capability_is_present_but_not_shipped() {
    let entry = settings_capability_catalog()
      .into_iter()
      .find(|e| e.capability_id == EVENTKIT_EVENTS_INVITATIONS)
      .expect("invitations");
    assert!(!entry.shipped);
  }

  #[test]
  fn uniffi_export_matches_catalog() {
    assert_eq!(list_settings_capabilities(), settings_capability_catalog());
  }
}

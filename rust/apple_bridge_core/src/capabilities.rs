//! Capability IDs for MCP tool gating (PR 3a allowlist).

pub const EVENTKIT_REMINDERS_READ: &str = "eventkit.reminders.read";
pub const EVENTKIT_REMINDERS_SEARCH: &str = "eventkit.reminders.search";

pub fn is_valid_capability_id(id: &str) -> bool {
  !id.is_empty()
    && id == id.to_lowercase()
    && !id.chars().any(char::is_whitespace)
    && id.split('.').count() >= 3
    && id
      .split('.')
      .all(|segment| !segment.is_empty() && segment == segment.to_lowercase())
}

pub fn is_allowed_in_v1(id: &str) -> bool {
  matches!(id, EVENTKIT_REMINDERS_READ | EVENTKIT_REMINDERS_SEARCH)
}

#[cfg(test)]
mod tests {
  use super::{EVENTKIT_REMINDERS_READ, EVENTKIT_REMINDERS_SEARCH, is_allowed_in_v1, is_valid_capability_id};

  #[test]
  fn accepts_read_capability_shape() {
    assert!(is_valid_capability_id(EVENTKIT_REMINDERS_READ));
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
  fn v1_allowlist_includes_read_and_search() {
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_READ));
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_SEARCH));
    assert!(!is_allowed_in_v1("eventkit.reminders.write"));
  }
}

//! Capability IDs for MCP tool gating (PR 3a allowlist).

pub const EVENTKIT_REMINDERS_READ: &str = "eventkit.reminders.read";

pub fn is_valid_capability_id(id: &str) -> bool {
  let trimmed = id.trim();
  !trimmed.is_empty()
    && trimmed == trimmed.to_lowercase()
    && !trimmed.chars().any(char::is_whitespace)
    && trimmed.split('.').count() >= 3
    && trimmed
      .split('.')
      .all(|segment| !segment.is_empty() && segment == segment.to_lowercase())
}

pub fn is_allowed_in_v1(id: &str) -> bool {
  matches!(id, EVENTKIT_REMINDERS_READ)
}

#[cfg(test)]
mod tests {
  use super::{EVENTKIT_REMINDERS_READ, is_allowed_in_v1, is_valid_capability_id};

  #[test]
  fn accepts_read_capability_shape() {
    assert!(is_valid_capability_id(EVENTKIT_REMINDERS_READ));
  }

  #[test]
  fn rejects_uppercase_capability() {
    assert!(!is_valid_capability_id("EventKit.Reminders.Read"));
  }

  #[test]
  fn v1_allowlist_includes_read() {
    assert!(is_allowed_in_v1(EVENTKIT_REMINDERS_READ));
    assert!(!is_allowed_in_v1("eventkit.reminders.write"));
  }
}

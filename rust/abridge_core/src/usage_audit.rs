//! Bounded in-memory usage audit log for diagnostics.

use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const MAX_ENTRIES: usize = 1000;

pub const EVENT_TOOL_CALL: &str = "tool_call";
pub const EVENT_SERVER_START: &str = "server_start";
pub const EVENT_SERVER_STOP: &str = "server_stop";
pub const EVENT_PORT_BIND: &str = "port_bind";
pub const EVENT_MCP_INITIALIZE: &str = "mcp_initialize";
pub const EVENT_API_KEY_ROTATION: &str = "api_key_rotation";

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub struct UsageLogResponse {
  pub logging_enabled: bool,
  pub entries: Vec<UsageAuditEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record, serde::Serialize)]
pub struct UsageAuditEntry {
  pub timestamp_utc: String,
  pub event_type: String,
  pub tool_name: Option<String>,
  pub success: bool,
  pub duration_ms: Option<u64>,
}

pub struct UsageAuditStore {
  entries: Mutex<VecDeque<UsageAuditEntry>>,
  logging_enabled: Mutex<bool>,
}

impl Default for UsageAuditStore {
  fn default() -> Self {
    Self::new()
  }
}

impl UsageAuditStore {
  pub fn new() -> Self {
    Self {
      entries: Mutex::new(VecDeque::with_capacity(MAX_ENTRIES)),
      logging_enabled: Mutex::new(true),
    }
  }

  pub fn record(&self, event_type: &str, tool_name: Option<&str>, success: bool, duration_ms: Option<u64>) {
    if !self.logging_enabled() {
      return;
    }

    let entry = UsageAuditEntry {
      timestamp_utc: utc_now_iso8601(),
      event_type: event_type.into(),
      tool_name: tool_name.map(str::to_owned),
      success,
      duration_ms,
    };

    let Ok(mut entries) = self.entries.lock() else {
      tracing::warn!("usage audit store lock poisoned; skipping record");
      return;
    };

    if entries.len() >= MAX_ENTRIES {
      entries.pop_front();
    }
    entries.push_back(entry);
  }

  pub fn entries(&self) -> Vec<UsageAuditEntry> {
    match self.entries.lock() {
      Ok(entries) => entries.iter().cloned().collect(),
      Err(_) => Vec::new(),
    }
  }

  pub fn entries_limited(&self, limit: Option<usize>) -> Vec<UsageAuditEntry> {
    let all = self.entries();
    match limit {
      Some(0) => Vec::new(),
      Some(n) if n < all.len() => all[all.len() - n..].to_vec(),
      _ => all,
    }
  }

  pub fn usage_log_response(&self, limit: Option<usize>) -> UsageLogResponse {
    UsageLogResponse {
      logging_enabled: self.logging_enabled(),
      entries: self.entries_limited(limit),
    }
  }

  pub fn set_logging_enabled(&self, enabled: bool) {
    if let Ok(mut guard) = self.logging_enabled.lock() {
      *guard = enabled;
    }
  }

  pub fn logging_enabled(&self) -> bool {
    match self.logging_enabled.lock() {
      Ok(guard) => *guard,
      Err(_) => false,
    }
  }
}

fn utc_now_iso8601() -> String {
  let duration = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or(Duration::ZERO);
  format_unix_timestamp_utc(duration.as_secs(), duration.subsec_millis())
}

fn format_unix_timestamp_utc(secs: u64, millis: u32) -> String {
  let days = secs / 86_400;
  let day_secs = secs % 86_400;
  let hours = day_secs / 3_600;
  let minutes = (day_secs % 3_600) / 60;
  let seconds = day_secs % 60;

  let (year, month, day) = civil_from_days(days as i64);

  format!("{year:04}-{month:02}-{day:02}T{hours:02}:{minutes:02}:{seconds:02}.{millis:03}Z")
}

/// Converts days since Unix epoch (1970-01-01) to a civil date.
fn civil_from_days(days: i64) -> (i32, u32, u32) {
  let z = days + 719_468;
  let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
  let doe = z - era * 146_097;
  let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
  let y = (yoe as i32) + era as i32 * 400;
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  let mp = (5 * doy + 2) / 153;
  let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
  let month = (mp + if mp < 10 { 3 } else { -9 }) as u32;
  let year = y + if month <= 2 { 1 } else { 0 };
  (year, month, day)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn ring_buffer_drops_oldest_at_capacity() {
    let store = UsageAuditStore::new();
    for index in 0..MAX_ENTRIES {
      store.record(&format!("event_{index}"), None, true, None);
    }
    store.record("overflow", None, true, None);

    let entries = store.entries();
    assert_eq!(entries.len(), MAX_ENTRIES);
    assert_eq!(entries.first().expect("first").event_type, "event_1");
    assert_eq!(entries.last().expect("last").event_type, "overflow");
  }

  #[test]
  fn disabled_logging_skips_record() {
    let store = UsageAuditStore::new();
    store.set_logging_enabled(false);
    store.record(EVENT_TOOL_CALL, Some("eventkit_reminders_list_lists"), true, Some(12));

    assert!(store.entries().is_empty());
    assert!(!store.logging_enabled());
  }

  #[test]
  fn serialized_json_has_no_sensitive_keys() {
    let store = UsageAuditStore::new();
    store.record(EVENT_TOOL_CALL, Some("eventkit_reminders_list_lists"), true, Some(42));

    let entry = store.entries().into_iter().next().expect("entry");
    let json = serde_json::to_string(&entry).expect("serialize");
    let value: serde_json::Value = serde_json::from_str(&json).expect("parse");

    let object = value.as_object().expect("object");
    assert!(!object.contains_key("bearer"));
    assert!(!object.contains_key("token"));
    assert!(!object.contains_key("payload"));
    assert_eq!(object.get("event_type").and_then(|v| v.as_str()), Some(EVENT_TOOL_CALL));
    assert_eq!(
      object.get("tool_name").and_then(|v| v.as_str()),
      Some("eventkit_reminders_list_lists")
    );
  }

  #[test]
  fn logging_enabled_defaults_true() {
    let store = UsageAuditStore::new();
    assert!(store.logging_enabled());
  }

  #[test]
  fn record_tool_call_stores_fields() {
    let store = UsageAuditStore::new();
    store.record(EVENT_TOOL_CALL, Some("my_tool"), false, Some(99));

    let entry = store.entries().into_iter().next().expect("entry");
    assert_eq!(entry.event_type, EVENT_TOOL_CALL);
    assert_eq!(entry.tool_name.as_deref(), Some("my_tool"));
    assert!(!entry.success);
    assert_eq!(entry.duration_ms, Some(99));
    assert!(entry.timestamp_utc.ends_with('Z'));
  }

  #[test]
  fn entries_limited_returns_most_recent_entries() {
    let store = UsageAuditStore::new();
    for index in 0..5 {
      store.record(&format!("event_{index}"), None, true, None);
    }

    let limited = store.entries_limited(Some(2));
    assert_eq!(limited.len(), 2);
    assert_eq!(limited[0].event_type, "event_3");
    assert_eq!(limited[1].event_type, "event_4");
  }

  #[test]
  fn usage_log_response_reflects_logging_enabled_flag() {
    let store = UsageAuditStore::new();
    store.record(EVENT_SERVER_START, None, true, None);
    store.set_logging_enabled(false);

    let response = store.usage_log_response(None);
    assert!(!response.logging_enabled);
    assert_eq!(response.entries.len(), 1);
    assert_eq!(response.entries[0].event_type, EVENT_SERVER_START);
  }

  #[test]
  fn utc_timestamp_format() {
    let formatted = format_unix_timestamp_utc(1_751_097_600, 42);
    assert_eq!(formatted, "2025-06-28T08:00:00.042Z");
  }
}

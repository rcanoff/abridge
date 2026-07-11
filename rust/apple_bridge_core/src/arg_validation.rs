//! Validate MCP tool call arguments against each tool's advertised `inputSchema`.
//!
//! Uses a focused JSON Schema subset matching schemas in `tools::input_schema`
//! (no external jsonschema crate — keeps MSRV 1.85 and a small staticlib surface).

use serde_json::Value;

use crate::tools::{self, ToolDefinition};

/// Validate `arguments` against the tool's existing input schema.
///
/// Returns `Ok(())` when valid; `Err(message)` describing the first failure.
pub fn validate_tool_arguments(tool: &ToolDefinition, arguments: &Value) -> Result<(), String> {
  let schema = tools::input_schema(tool);
  validate_against_schema(&schema, arguments, "$")
}

fn validate_against_schema(schema: &Value, instance: &Value, path: &str) -> Result<(), String> {
  // Sibling keywords are conjunctive with oneOf/anyOf (JSON Schema).
  // `oneOf` requires exactly one successful alternative.
  if let Some(one_of) = schema.get("oneOf").and_then(Value::as_array) {
    let mut errors = Vec::new();
    let mut match_count = 0usize;
    for (index, sub) in one_of.iter().enumerate() {
      match validate_against_schema(sub, instance, path) {
        Ok(()) => match_count += 1,
        Err(err) => errors.push(format!("oneOf[{index}]: {err}")),
      }
    }
    if match_count != 1 {
      return Err(format!(
        "{path}: oneOf requires exactly one matching alternative (matched {match_count}; {})",
        errors.join("; ")
      ));
    }
  }

  if let Some(any_of) = schema.get("anyOf").and_then(Value::as_array) {
    let mut errors = Vec::new();
    let mut matched = false;
    for (index, sub) in any_of.iter().enumerate() {
      match validate_against_schema(sub, instance, path) {
        Ok(()) => {
          matched = true;
          break;
        }
        Err(err) => errors.push(format!("anyOf[{index}]: {err}")),
      }
    }
    if !matched {
      return Err(format!(
        "{path}: does not match any anyOf alternative ({})",
        errors.join("; ")
      ));
    }
  }

  if let Some(not_schema) = schema.get("not") {
    if validate_against_schema(not_schema, instance, path).is_ok() {
      return Err(format!("{path}: matches forbidden (not) schema"));
    }
  }

  if let Some(type_value) = schema.get("type") {
    check_type(type_value, instance, path)?;
  }

  if let Some(enum_values) = schema.get("enum").and_then(Value::as_array) {
    if !enum_values.iter().any(|candidate| candidate == instance) {
      return Err(format!("{path}: value is not in enum"));
    }
  }

  if let Some(minimum) = schema.get("minimum").and_then(Value::as_f64) {
    if let Some(number) = instance.as_f64() {
      if number < minimum {
        return Err(format!("{path}: {number} is below minimum {minimum}"));
      }
    }
  }

  if let Some(maximum) = schema.get("maximum").and_then(Value::as_f64) {
    if let Some(number) = instance.as_f64() {
      if number > maximum {
        return Err(format!("{path}: {number} is above maximum {maximum}"));
      }
    }
  }

  if let Some(min_length) = schema.get("minLength").and_then(Value::as_u64) {
    if let Some(text) = instance.as_str() {
      if (text.chars().count() as u64) < min_length {
        return Err(format!("{path}: string shorter than minLength {min_length}"));
      }
    }
  }

  if let Some(pattern) = schema.get("pattern").and_then(Value::as_str) {
    if let Some(text) = instance.as_str() {
      // Schemas use simple patterns such as `.*\S.*` (non-whitespace required).
      if pattern == r".*\S.*" && !text.chars().any(|c| !c.is_whitespace()) {
        return Err(format!("{path}: string must contain non-whitespace characters"));
      }
    }
  }

  if schema.get("format").and_then(Value::as_str) == Some("date-time") {
    if let Some(text) = instance.as_str() {
      if !looks_like_iso8601_date_time(text) {
        return Err(format!("{path}: expected date-time format string"));
      }
    }
  }

  if let Some(required) = schema.get("required").and_then(Value::as_array) {
    let object = instance
      .as_object()
      .ok_or_else(|| format!("{path}: expected object for required-field checks"))?;
    for key in required {
      let Some(key) = key.as_str() else {
        continue;
      };
      if !object.contains_key(key) {
        return Err(format!("{path}: missing required property '{key}'"));
      }
    }
  }

  if let Some(properties) = schema.get("properties").and_then(Value::as_object) {
    if let Some(object) = instance.as_object() {
      for (key, prop_schema) in properties {
        if let Some(value) = object.get(key) {
          let child_path = format!("{path}.{key}");
          validate_against_schema(prop_schema, value, &child_path)?;
        }
      }
    }
  }

  if let Some(items_schema) = schema.get("items") {
    if let Some(array) = instance.as_array() {
      for (index, item) in array.iter().enumerate() {
        let child_path = format!("{path}[{index}]");
        validate_against_schema(items_schema, item, &child_path)?;
      }
    }
  }

  Ok(())
}

fn check_type(type_value: &Value, instance: &Value, path: &str) -> Result<(), String> {
  match type_value {
    Value::String(type_name) => {
      if instance_matches_type(type_name, instance) {
        Ok(())
      } else {
        Err(format!(
          "{path}: expected type {type_name}, got {}",
          json_type_name(instance)
        ))
      }
    }
    Value::Array(types) => {
      let ok = types.iter().any(|entry| {
        entry
          .as_str()
          .is_some_and(|type_name| instance_matches_type(type_name, instance))
      });
      if ok {
        Ok(())
      } else {
        Err(format!(
          "{path}: expected one of types {types:?}, got {}",
          json_type_name(instance)
        ))
      }
    }
    _ => Ok(()),
  }
}

fn instance_matches_type(type_name: &str, instance: &Value) -> bool {
  match type_name {
    "object" => instance.is_object(),
    "array" => instance.is_array(),
    "string" => instance.is_string(),
    "boolean" => instance.is_boolean(),
    "null" => instance.is_null(),
    "integer" => instance.as_i64().is_some() || instance.as_u64().is_some(),
    "number" => instance.as_f64().is_some(),
    _ => true,
  }
}

fn json_type_name(instance: &Value) -> &'static str {
  match instance {
    Value::Null => "null",
    Value::Bool(_) => "boolean",
    Value::Number(n) if n.is_i64() || n.is_u64() => "integer",
    Value::Number(_) => "number",
    Value::String(_) => "string",
    Value::Array(_) => "array",
    Value::Object(_) => "object",
  }
}

/// RFC 3339 / ISO-8601 date-time subset used by MCP tool schemas.
/// Accepts `YYYY-MM-DDTHH:MM:SS[.fff]Z` or offset `±HH:MM`.
fn looks_like_iso8601_date_time(text: &str) -> bool {
  parse_rfc3339_date_time(text).is_ok()
}

fn parse_rfc3339_date_time(text: &str) -> Result<(), ()> {
  let (date, rest) = text.split_once('T').or_else(|| text.split_once('t')).ok_or(())?;
  // full-date = YYYY-MM-DD (fixed widths)
  if date.len() != 10 || date.as_bytes().get(4) != Some(&b'-') || date.as_bytes().get(7) != Some(&b'-') {
    return Err(());
  }
  let year = parse_fixed_digits(&date[0..4], 4)? as i32;
  let month = parse_fixed_digits(&date[5..7], 2)?;
  let day = parse_fixed_digits(&date[8..10], 2)?;
  if !(1..=12).contains(&month) {
    return Err(());
  }
  if day == 0 || day > days_in_month(year, month) {
    return Err(());
  }

  let (time, offset) = split_time_and_offset(rest)?;
  // partial-time = HH:MM:SS[.fff...] with fixed HH/MM/SS widths
  let (second_raw, hour_minute) = {
    let bytes = time.as_bytes();
    if bytes.len() < 8 || bytes.get(2) != Some(&b':') || bytes.get(5) != Some(&b':') {
      return Err(());
    }
    (&time[6..], &time[0..5])
  };
  let hour = parse_fixed_digits(&hour_minute[0..2], 2)?;
  let minute = parse_fixed_digits(&hour_minute[3..5], 2)?;
  if hour > 23 || minute > 59 {
    return Err(());
  }
  let (second_str, fraction) = match second_raw.split_once('.') {
    Some((sec, frac)) => (sec, Some(frac)),
    None => (second_raw, None),
  };
  if second_str.len() != 2 {
    return Err(());
  }
  let second = parse_fixed_digits(second_str, 2)?;
  if second > 60 {
    return Err(());
  }
  if let Some(frac) = fraction {
    if frac.is_empty() || !frac.chars().all(|c| c.is_ascii_digit()) {
      return Err(());
    }
  }
  validate_offset(offset)
}

fn parse_fixed_digits(text: &str, width: usize) -> Result<u32, ()> {
  if text.len() != width || !text.bytes().all(|b| b.is_ascii_digit()) {
    return Err(());
  }
  text.parse().map_err(|_| ())
}

fn days_in_month(year: i32, month: u32) -> u32 {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
    4 | 6 | 9 | 11 => 30,
    2 if is_leap_year(year) => 29,
    2 => 28,
    _ => 0,
  }
}

fn is_leap_year(year: i32) -> bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

fn split_time_and_offset(rest: &str) -> Result<(&str, &str), ()> {
  if let Some(time) = rest.strip_suffix('Z').or_else(|| rest.strip_suffix('z')) {
    return Ok((time, "Z"));
  }
  if let Some(idx) = rest.rfind(['+', '-']) {
    if idx == 0 {
      return Err(());
    }
    return Ok((&rest[..idx], &rest[idx..]));
  }
  Err(())
}

fn validate_offset(offset: &str) -> Result<(), ()> {
  if offset.eq_ignore_ascii_case("Z") {
    return Ok(());
  }
  if offset.len() != 6 {
    return Err(());
  }
  let bytes = offset.as_bytes();
  if bytes[0] != b'+' && bytes[0] != b'-' {
    return Err(());
  }
  if bytes[3] != b':' {
    return Err(());
  }
  let hours: u32 = std::str::from_utf8(&bytes[1..3])
    .map_err(|_| ())?
    .parse()
    .map_err(|_| ())?;
  let minutes: u32 = std::str::from_utf8(&bytes[4..6])
    .map_err(|_| ())?
    .parse()
    .map_err(|_| ())?;
  if hours > 23 || minutes > 59 {
    return Err(());
  }
  Ok(())
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::tools::{TOOL_CREATE_EVENT, TOOL_CREATE_REMINDER, TOOL_GET_EVENT, TOOL_LIST_LISTS, resolve_tool};
  use serde_json::json;

  #[test]
  fn rejects_get_event_without_identifier() {
    let tool = resolve_tool(TOOL_GET_EVENT).expect("tool");
    let err = validate_tool_arguments(tool, &json!({})).expect_err("should fail");
    assert!(err.contains("event_identifier"), "{err}");
  }

  #[test]
  fn accepts_get_event_with_identifier() {
    let tool = resolve_tool(TOOL_GET_EVENT).expect("tool");
    validate_tool_arguments(tool, &json!({ "event_identifier": "e1" })).expect("valid");
  }

  #[test]
  fn rejects_create_event_missing_required() {
    let tool = resolve_tool(TOOL_CREATE_EVENT).expect("tool");
    let err = validate_tool_arguments(tool, &json!({ "calendar_identifier": "c1" })).expect_err("fail");
    assert!(
      err.contains("title") || err.contains("start_date") || err.contains("end_date") || err.contains("required"),
      "{err}"
    );
  }

  #[test]
  fn accepts_empty_object_for_list_lists() {
    let tool = resolve_tool(TOOL_LIST_LISTS).expect("tool");
    validate_tool_arguments(tool, &json!({})).expect("valid");
  }

  #[test]
  fn one_of_rejects_when_multiple_alternatives_match() {
    let schema = json!({
      "oneOf": [
        { "type": "string" },
        { "type": "string", "minLength": 1 }
      ]
    });
    let err = validate_against_schema(&schema, &json!("ab"), "$").expect_err("multi match");
    assert!(err.contains("exactly one"), "{err}");
  }

  #[test]
  fn date_time_rejects_impossible_calendar_values() {
    let schema = json!({ "type": "string", "format": "date-time" });
    let err = validate_against_schema(&schema, &json!("2024-99-99T12:00:00Z"), "$").expect_err("bad date");
    assert!(err.contains("date-time"), "{err}");
  }

  #[test]
  fn date_time_accepts_rfc3339_utc() {
    let schema = json!({ "type": "string", "format": "date-time" });
    validate_against_schema(&schema, &json!("2024-01-15T12:30:00Z"), "$").expect("valid");
  }

  #[test]
  fn date_time_rejects_non_fixed_width_components() {
    let schema = json!({ "type": "string", "format": "date-time" });
    let err = validate_against_schema(&schema, &json!("2024-1-5T1:2:3Z"), "$").expect_err("bad width");
    assert!(err.contains("date-time"), "{err}");
  }

  #[test]
  fn create_reminder_schema_rejects_whitespace_only_title() {
    let tool = resolve_tool(TOOL_CREATE_REMINDER).expect("tool");
    let err = validate_tool_arguments(tool, &json!({ "calendar_identifier": "c1", "title": "   " }))
      .expect_err("whitespace title");
    assert!(
      err.contains("non-whitespace") || err.contains("title") || err.contains("pattern"),
      "{err}"
    );
  }

  #[test]
  fn create_reminder_schema_rejects_priority_out_of_range() {
    let tool = resolve_tool(TOOL_CREATE_REMINDER).expect("tool");
    let err = validate_tool_arguments(
      tool,
      &json!({ "calendar_identifier": "c1", "title": "T", "priority": 99 }),
    )
    .expect_err("priority");
    assert!(
      err.contains("maximum") || err.contains("priority") || err.contains("99"),
      "{err}"
    );
  }
}

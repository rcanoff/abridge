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
  if let Some(one_of) = schema.get("oneOf").and_then(Value::as_array) {
    let mut errors = Vec::new();
    let mut matched = false;
    for (index, sub) in one_of.iter().enumerate() {
      match validate_against_schema(sub, instance, path) {
        Ok(()) => {
          matched = true;
          break;
        }
        Err(err) => errors.push(format!("oneOf[{index}]: {err}")),
      }
    }
    if !matched {
      return Err(format!(
        "{path}: does not match any oneOf alternative ({})",
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

/// Lenient ISO-8601 / RFC 3339 check (presence of date and time separators).
fn looks_like_iso8601_date_time(text: &str) -> bool {
  // Accept common EventKit/MCP forms: `2024-01-01T12:00:00Z`, with offset, fractional seconds.
  if text.len() < 16 {
    return false;
  }
  let bytes = text.as_bytes();
  bytes.get(4) == Some(&b'-')
    && bytes.get(7) == Some(&b'-')
    && (bytes.get(10) == Some(&b'T') || bytes.get(10) == Some(&b't') || bytes.get(10) == Some(&b' '))
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::tools::{TOOL_CREATE_EVENT, TOOL_GET_EVENT, TOOL_LIST_LISTS, resolve_tool};
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
}

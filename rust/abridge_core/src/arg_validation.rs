//! Validate MCP tool call arguments against each tool's advertised `inputSchema`.
//!
//! Uses a focused JSON Schema subset matching schemas in `tools::input_schema`
//! (no external jsonschema crate — keeps the staticlib surface small).

use serde_json::Value;

use crate::tools::{self, ToolDefinition};

/// Validate `arguments` against the tool's existing input schema.
///
/// Returns `Ok(())` when valid; `Err(message)` describing the first failure.
pub fn validate_tool_arguments(tool: &ToolDefinition, arguments: &Value) -> Result<(), String> {
  let schema = tools::input_schema(tool);
  validate_against_schema(&schema, arguments, "$")?;
  // Rules that used to be top-level oneOf/anyOf. Clients reject those combinators, so the
  // schema stays a plain object and the same constraints are checked here before dispatch.
  validate_cross_field_rules(tool, arguments)
}

fn validate_cross_field_rules(tool: &ToolDefinition, arguments: &Value) -> Result<(), String> {
  match tool.name {
    tools::TOOL_SEARCH_CONTACTS => require_any(
      arguments,
      &["query", "name", "email_address", "phone_number"],
      "Provide at least one of query, name, email_address, or phone_number.",
    ),
    tools::TOOL_CREATE_CONTACT => require_any(
      arguments,
      &["given_name", "family_name", "organization_name"],
      "Provide at least one of given_name, family_name, or organization_name.",
    ),
    tools::TOOL_ESTIMATE_TRAVEL_TIME | tools::TOOL_CALCULATE_ROUTE => {
      reject_both_present(
        arguments,
        "departure_date",
        "arrival_date",
        "Provide exactly one of departure_date or arrival_date, or neither.",
      )?;
      require_route_endpoint(arguments, "source")?;
      require_route_endpoint(arguments, "destination")?;
      require_waypoints(arguments)
    }
    tools::TOOL_OPEN_NAVIGATION => {
      require_route_endpoint(arguments, "source")?;
      require_route_endpoint(arguments, "destination")?;
      require_waypoints(arguments)
    }
    tools::TOOL_SEARCH_NEARBY => require_exactly_one(
      arguments,
      "coordinate",
      "region",
      "Provide exactly one of coordinate (with optional radius_meters) or region.",
    ),
    tools::TOOL_RECOGNIZE_TEXT
    | tools::TOOL_RECOGNIZE_DOCUMENTS
    | tools::TOOL_DETECT_BARCODES
    | tools::TOOL_DETECT_FACE_LANDMARKS => require_vision_image(arguments),
    tools::TOOL_NOTES_LIST_NOTES | tools::TOOL_NOTES_SEARCH_NOTES => require_notes_folder(arguments, false),
    tools::TOOL_NOTES_CREATE_NOTE | tools::TOOL_NOTES_DELETE_FOLDER => require_notes_folder(arguments, true),
    tools::TOOL_NOTES_GET_NOTE | tools::TOOL_NOTES_UPDATE_NOTE | tools::TOOL_NOTES_DELETE_NOTE => {
      require_note_identity(arguments)?;
      require_notes_folder(arguments, false)
    }
    tools::TOOL_NOTES_MOVE_NOTE => {
      require_note_identity(arguments)?;
      require_notes_folder(arguments, true)
    }
    tools::TOOL_NOTES_CREATE_FOLDER => require_create_folder_parent(arguments),
    tools::TOOL_CREATE_EVENT | tools::TOOL_UPDATE_EVENT => validate_event_dates(arguments),
    tools::TOOL_DELETE_REMINDER => require_exactly_one(
      arguments,
      "calendar_item_identifier",
      "reminder_title",
      "Provide exactly one of calendar_item_identifier or reminder_title.",
    ),
    tools::TOOL_DELETE_EVENT => require_exactly_one(
      arguments,
      "event_identifier",
      "event_title",
      "Provide exactly one of event_identifier or event_title.",
    ),
    _ => Ok(()),
  }
}

/// Timed event inputs need an offset or `time_zone`. All-day date-only values stay calendar dates.
/// Nothing here is read in the server's zone.
fn validate_event_dates(arguments: &Value) -> Result<(), String> {
  let all_day = arguments.get("is_all_day").and_then(Value::as_bool) == Some(true);
  let zone = arguments
    .get("time_zone")
    .and_then(Value::as_str)
    .filter(|zone| !zone.is_empty());
  for key in ["start_date", "end_date"] {
    let Some(text) = arguments.get(key).and_then(Value::as_str) else {
      continue;
    };
    crate::datetime::normalize_event_date(key, text, all_day, zone)?;
  }
  Ok(())
}

fn require_notes_folder(arguments: &Value, required: bool) -> Result<(), String> {
  let identifier = argument_present(arguments, "folder_identifier");
  let path = argument_present(arguments, "folder_path");
  let account = argument_present(arguments, "account_identifier");
  if identifier && path {
    return Err(format!("$: {}", crate::notes::FOLDER_EXACTLY_ONE));
  }
  if account && !path {
    return Err(format!("$: {}", crate::notes::ACCOUNT_ONLY_WITH_PATH));
  }
  if required && !identifier && !path {
    return Err(format!("$: {}", crate::notes::FOLDER_EXACTLY_ONE));
  }
  Ok(())
}

fn require_note_identity(arguments: &Value) -> Result<(), String> {
  let identifier = argument_present(arguments, "note_identifier");
  let title = argument_present(arguments, "note_title");
  if identifier == title {
    Err(format!("$: {}", crate::notes::NOTE_EXACTLY_ONE))
  } else {
    Ok(())
  }
}

fn require_create_folder_parent(arguments: &Value) -> Result<(), String> {
  let identifier = argument_present(arguments, "folder_identifier");
  let path = argument_present(arguments, "folder_path");
  let account = argument_present(arguments, "account_identifier");
  if identifier && path {
    return Err(format!("$: {}", crate::notes::FOLDER_EXACTLY_ONE));
  }
  let ok = matches!(
    (account, identifier, path),
    (true, false, false) | (false, true, false) | (_, false, true)
  );
  if ok {
    Ok(())
  } else {
    Err(format!("$: {}", crate::notes::CREATE_FOLDER_PARENT))
  }
}

fn argument_present(arguments: &Value, key: &str) -> bool {
  arguments.as_object().is_some_and(|object| object.contains_key(key))
}

fn require_any(arguments: &Value, keys: &[&str], message: &str) -> Result<(), String> {
  if keys.iter().any(|key| argument_present(arguments, key)) {
    Ok(())
  } else {
    Err(format!("$: {message}"))
  }
}

fn reject_both_present(arguments: &Value, left: &str, right: &str, message: &str) -> Result<(), String> {
  if argument_present(arguments, left) && argument_present(arguments, right) {
    Err(format!("$: {message}"))
  } else {
    Ok(())
  }
}

fn require_route_endpoint(arguments: &Value, key: &str) -> Result<(), String> {
  let Some(endpoint) = arguments.get(key).filter(|endpoint| endpoint.is_object()) else {
    return Ok(());
  };
  if endpoint_has_location(endpoint) {
    Ok(())
  } else {
    Err(format!("$: {key} needs a coordinate or a MapKit place identifier"))
  }
}

fn require_waypoints(arguments: &Value) -> Result<(), String> {
  let Some(waypoints) = arguments.get("waypoints").and_then(Value::as_array) else {
    return Ok(());
  };
  for (index, waypoint) in waypoints.iter().enumerate() {
    if !endpoint_has_location(waypoint) {
      return Err(format!(
        "$: waypoints[{index}] needs a coordinate or a MapKit place identifier"
      ));
    }
  }
  Ok(())
}

fn endpoint_has_location(endpoint: &Value) -> bool {
  let has_coordinate = endpoint.get("coordinate").and_then(Value::as_object).is_some();
  let has_identifier = endpoint
    .get("identifier")
    .and_then(Value::as_str)
    .is_some_and(|identifier| !identifier.trim().is_empty());
  has_coordinate || has_identifier
}

fn require_vision_image(arguments: &Value) -> Result<(), String> {
  require_exactly_one(
    arguments,
    "image_data",
    "image_path",
    "Provide exactly one of image_data or image_path.",
  )?;
  if let Some(path) = arguments.get("image_path").and_then(Value::as_str)
    && !path.starts_with('/')
  {
    return Err("$: image_path must be an absolute path".to_string());
  }
  Ok(())
}

fn require_exactly_one(arguments: &Value, left: &str, right: &str, message: &str) -> Result<(), String> {
  let left_present = argument_present(arguments, left);
  let right_present = argument_present(arguments, right);
  if left_present == right_present {
    Err(format!("$: {message}"))
  } else {
    Ok(())
  }
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

  if let Some(not_schema) = schema.get("not")
    && validate_against_schema(not_schema, instance, path).is_ok()
  {
    return Err(format!("{path}: matches forbidden (not) schema"));
  }

  if let Some(type_value) = schema.get("type") {
    check_type(type_value, instance, path)?;
  }

  if let Some(enum_values) = schema.get("enum").and_then(Value::as_array)
    && !enum_values.iter().any(|candidate| candidate == instance)
  {
    return Err(format!("{path}: value is not in enum"));
  }

  if let Some(minimum) = schema.get("minimum").and_then(Value::as_f64)
    && let Some(number) = instance.as_f64()
    && number < minimum
  {
    return Err(format!("{path}: {number} is below minimum {minimum}"));
  }

  if let Some(minimum) = schema.get("exclusiveMinimum").and_then(Value::as_f64)
    && let Some(number) = instance.as_f64()
    && number <= minimum
  {
    return Err(format!("{path}: {number} must be greater than {minimum}"));
  }

  if let Some(maximum) = schema.get("maximum").and_then(Value::as_f64)
    && let Some(number) = instance.as_f64()
    && number > maximum
  {
    return Err(format!("{path}: {number} is above maximum {maximum}"));
  }

  if let Some(min_length) = schema.get("minLength").and_then(Value::as_u64)
    && let Some(text) = instance.as_str()
    && (text.chars().count() as u64) < min_length
  {
    return Err(format!("{path}: string shorter than minLength {min_length}"));
  }

  if let Some(pattern) = schema.get("pattern").and_then(Value::as_str)
    && let Some(text) = instance.as_str()
    && pattern == r".*\S.*"
    && !text.chars().any(|c| !c.is_whitespace())
  {
    return Err(format!("{path}: string must contain non-whitespace characters"));
  }
  if schema.get("format").and_then(Value::as_str) == Some("date-time")
    && let Some(text) = instance.as_str()
    && !looks_like_iso8601_date_time(text)
  {
    return Err(format!(
      "{path}: expected a date-time with a numeric offset (Z or ±HH:MM); the server's time zone is not used"
    ));
  }

  if let Some(max_items) = schema.get("maxItems").and_then(Value::as_u64)
    && let Some(array) = instance.as_array()
    && array.len() as u64 > max_items
  {
    return Err(format!("{path}: at most {max_items} items"));
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

  if let Some(properties) = schema.get("properties").and_then(Value::as_object)
    && let Some(object) = instance.as_object()
  {
    for (key, prop_schema) in properties {
      if let Some(value) = object.get(key) {
        let child_path = format!("{path}.{key}");
        validate_against_schema(prop_schema, value, &child_path)?;
      }
    }
  }
  if let Some(items_schema) = schema.get("items")
    && let Some(array) = instance.as_array()
  {
    for (index, item) in array.iter().enumerate() {
      let child_path = format!("{path}[{index}]");
      validate_against_schema(items_schema, item, &child_path)?;
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

/// Strict RFC 3339 used by every `format: date-time` argument (list bounds, reminder windows,
/// notes `modified_after`/`modified_before`, MapKit dates).
fn looks_like_iso8601_date_time(text: &str) -> bool {
  crate::datetime::parse_rfc3339(text).is_some()
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::tools::{
    TOOL_CALCULATE_ROUTE, TOOL_CREATE_CONTACT, TOOL_CREATE_EVENT, TOOL_CREATE_REMINDER, TOOL_DELETE_EVENT,
    TOOL_DELETE_REMINDER, TOOL_DETECT_BARCODES, TOOL_DETECT_FACE_LANDMARKS, TOOL_ESTIMATE_TRAVEL_TIME, TOOL_GET_EVENT,
    TOOL_LIST_EVENTS, TOOL_LIST_LISTS, TOOL_NOTES_CREATE_FOLDER, TOOL_NOTES_DELETE_NOTE, TOOL_NOTES_GET_NOTE,
    TOOL_NOTES_LIST_NOTES, TOOL_NOTES_MOVE_NOTE, TOOL_RECOGNIZE_DOCUMENTS, TOOL_RECOGNIZE_TEXT, TOOL_SEARCH_CONTACTS,
    TOOL_UPDATE_EVENT, resolve_tool,
  };
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
  fn search_contacts_requires_one_search_field() {
    let tool = resolve_tool(TOOL_SEARCH_CONTACTS).expect("tool");
    let missing = validate_tool_arguments(tool, &json!({})).expect_err("no criterion");
    assert!(missing.contains("at least one of query"), "{missing}");
    let container_only =
      validate_tool_arguments(tool, &json!({ "container_identifier": "c" })).expect_err("container only");
    assert!(container_only.contains("phone_number"), "{container_only}");
    validate_tool_arguments(tool, &json!({ "query": "ada" })).expect("query");
    validate_tool_arguments(tool, &json!({ "name": "Ada" })).expect("name");
    validate_tool_arguments(tool, &json!({ "email_address": "a@b.c" })).expect("email");
    validate_tool_arguments(tool, &json!({ "phone_number": "555" })).expect("phone");
    validate_tool_arguments(tool, &json!({ "name": "Ada", "query": "ada" })).expect("several");
  }

  #[test]
  fn create_contact_requires_one_name_field() {
    let tool = resolve_tool(TOOL_CREATE_CONTACT).expect("tool");
    let missing = validate_tool_arguments(tool, &json!({ "container_identifier": "c" })).expect_err("no name");
    assert!(
      missing.contains("given_name") && missing.contains("organization_name"),
      "{missing}"
    );
    validate_tool_arguments(tool, &json!({ "container_identifier": "c", "given_name": "Ada" })).expect("given");
    validate_tool_arguments(tool, &json!({ "container_identifier": "c", "family_name": "Lovelace" })).expect("family");
    validate_tool_arguments(
      tool,
      &json!({ "container_identifier": "c", "organization_name": "Analytical" }),
    )
    .expect("organization");
    validate_tool_arguments(
      tool,
      &json!({
        "container_identifier": "c",
        "given_name": "Ada",
        "family_name": "Lovelace",
        "organization_name": "Analytical"
      }),
    )
    .expect("all three");
    validate_tool_arguments(tool, &json!({ "given_name": "Ada" })).expect("default container");
    validate_tool_arguments(
      tool,
      &json!({
        "given_name": "Ada",
        "phone_numbers": [{ "label": "mobile", "value": "555-0100" }],
        "email_addresses": [{ "value": "ada@example.com" }],
        "postal_addresses": [{ "label": "home", "value": { "street": "1 Main", "city": "Town" } }]
      }),
    )
    .expect("read shape");
    assert!(
      validate_tool_arguments(
        tool,
        &json!({
          "given_name": "Ada",
          "phone_numbers": [{ "value": { "string_value": "555-0100" } }]
        }),
      )
      .is_err(),
      "phone values are strings, matching contacts_get_contact"
    );
  }

  #[test]
  fn estimate_travel_time_rejects_both_dates() {
    let tool = resolve_tool(TOOL_ESTIMATE_TRAVEL_TIME).expect("tool");
    let endpoint = json!({ "coordinate": { "latitude": 37.0, "longitude": -122.0 } });
    let neither = json!({ "source": endpoint.clone(), "destination": endpoint.clone() });
    validate_tool_arguments(tool, &neither).expect("neither date");
    validate_tool_arguments(
      tool,
      &json!({
        "source": endpoint.clone(),
        "destination": endpoint.clone(),
        "departure_date": "2026-03-24T12:00:00Z"
      }),
    )
    .expect("departure only");
    validate_tool_arguments(
      tool,
      &json!({
        "source": endpoint.clone(),
        "destination": endpoint.clone(),
        "arrival_date": "2026-03-24T18:00:00Z"
      }),
    )
    .expect("arrival only");
    let both = validate_tool_arguments(
      tool,
      &json!({
        "source": endpoint.clone(),
        "destination": endpoint,
        "departure_date": "2026-03-24T12:00:00Z",
        "arrival_date": "2026-03-24T18:00:00Z"
      }),
    )
    .expect_err("both dates");
    assert!(both.contains("departure_date") && both.contains("or neither"), "{both}");
  }

  #[test]
  fn route_endpoint_accepts_coordinate_or_place_identifier() {
    let tool = resolve_tool(TOOL_CALCULATE_ROUTE).expect("tool");
    let coordinate = json!({ "coordinate": { "latitude": 38.7, "longitude": -9.1 }, "name": "Tower" });
    validate_tool_arguments(
      tool,
      &json!({ "source": coordinate, "destination": { "identifier": "place-1" } }),
    )
    .expect("identifier destination");
    let missing = validate_tool_arguments(
      tool,
      &json!({ "source": coordinate, "destination": { "name": "Somewhere" } }),
    )
    .expect_err("name only");
    assert!(missing.contains("MapKit place identifier"), "{missing}");
  }

  #[test]
  fn vision_image_requires_exactly_one_source() {
    let tool = resolve_tool(TOOL_RECOGNIZE_TEXT).expect("tool");
    validate_tool_arguments(tool, &json!({ "image_data": "aGVsbG8=" })).expect("base64");
    validate_tool_arguments(tool, &json!({ "image_path": "/tmp/receipt.png" })).expect("path");
    let neither = validate_tool_arguments(tool, &json!({})).expect_err("neither");
    assert!(neither.contains("exactly one of image_data or image_path"), "{neither}");
    let both = validate_tool_arguments(
      tool,
      &json!({ "image_data": "aGVsbG8=", "image_path": "/tmp/receipt.png" }),
    )
    .expect_err("both");
    assert!(both.contains("exactly one"), "{both}");
    let relative = validate_tool_arguments(tool, &json!({ "image_path": "receipt.png" })).expect_err("relative");
    assert!(relative.contains("absolute path"), "{relative}");
  }

  #[test]
  fn vision_page_is_an_integer_at_least_one() {
    for name in [
      TOOL_RECOGNIZE_TEXT,
      TOOL_RECOGNIZE_DOCUMENTS,
      TOOL_DETECT_BARCODES,
      TOOL_DETECT_FACE_LANDMARKS,
    ] {
      let tool = resolve_tool(name).expect(name);
      validate_tool_arguments(tool, &json!({ "image_data": "aGVsbG8=" })).expect("omitted page");
      validate_tool_arguments(tool, &json!({ "image_data": "aGVsbG8=", "page": 1 })).expect("page 1");
      validate_tool_arguments(tool, &json!({ "image_path": "/tmp/scan.pdf", "page": 2 })).expect("page 2");
      let zero = validate_tool_arguments(tool, &json!({ "image_data": "aGVsbG8=", "page": 0 })).expect_err("zero");
      assert!(zero.contains("page") && zero.contains("minimum"), "{name}: {zero}");
      let fraction =
        validate_tool_arguments(tool, &json!({ "image_data": "aGVsbG8=", "page": 1.5 })).expect_err("fraction");
      assert!(fraction.contains("integer"), "{name}: {fraction}");
      let text = validate_tool_arguments(tool, &json!({ "image_data": "aGVsbG8=", "page": "2" })).expect_err("text");
      assert!(text.contains("integer"), "{name}: {text}");
    }
  }

  #[test]
  fn create_folder_requires_exactly_one_parent() {
    let tool = resolve_tool(TOOL_NOTES_CREATE_FOLDER).expect("tool");
    let neither = validate_tool_arguments(tool, &json!({ "name": "Inbox" })).expect_err("neither parent");
    assert!(neither.contains("folder_path"), "{neither}");
    let both = validate_tool_arguments(
      tool,
      &json!({ "name": "Inbox", "account_identifier": "acct", "folder_identifier": "parent" }),
    )
    .expect_err("both parents");
    assert!(both.contains("folder_identifier"), "{both}");
    let both_folders = validate_tool_arguments(
      tool,
      &json!({ "name": "Inbox", "folder_identifier": "parent", "folder_path": "Notes" }),
    )
    .expect_err("identifier and path");
    assert!(
      both_folders.contains("exactly one of folder_identifier or folder_path"),
      "{both_folders}"
    );
    validate_tool_arguments(tool, &json!({ "name": "Inbox", "account_identifier": "acct" })).expect("account");
    validate_tool_arguments(tool, &json!({ "name": "Inbox", "folder_identifier": "parent" })).expect("folder");
    validate_tool_arguments(
      tool,
      &json!({ "name": "Inbox", "folder_path": "Work/Clients", "account_identifier": "acct" }),
    )
    .expect("path");
  }

  #[test]
  fn notes_identity_and_folder_require_exactly_one() {
    let get = resolve_tool(TOOL_NOTES_GET_NOTE).expect("tool");
    let neither = validate_tool_arguments(get, &json!({})).expect_err("neither note");
    assert!(
      neither.contains("exactly one of note_identifier or note_title"),
      "{neither}"
    );
    let both =
      validate_tool_arguments(get, &json!({ "note_identifier": "n", "note_title": "Title" })).expect_err("both notes");
    assert!(both.contains("exactly one of note_identifier or note_title"), "{both}");
    validate_tool_arguments(get, &json!({ "note_title": "Title", "folder_path": "Notes" })).expect("title");

    let list = resolve_tool(TOOL_NOTES_LIST_NOTES).expect("tool");
    let both_folders = validate_tool_arguments(list, &json!({ "folder_identifier": "fold", "folder_path": "Notes" }))
      .expect_err("both folders");
    assert!(
      both_folders.contains("exactly one of folder_identifier or folder_path"),
      "{both_folders}"
    );
    let account_only = validate_tool_arguments(list, &json!({ "account_identifier": "acct" })).expect_err("account");
    assert!(
      account_only.contains("account_identifier applies only with folder_path"),
      "{account_only}"
    );

    let delete = resolve_tool(TOOL_NOTES_DELETE_NOTE).expect("tool");
    validate_tool_arguments(delete, &json!({ "note_identifier": "n" })).expect("identifier");
    let moved = resolve_tool(TOOL_NOTES_MOVE_NOTE).expect("tool");
    let missing_folder = validate_tool_arguments(moved, &json!({ "note_title": "Title" })).expect_err("folder");
    assert!(
      missing_folder.contains("exactly one of folder_identifier or folder_path"),
      "{missing_folder}"
    );
    validate_tool_arguments(
      moved,
      &json!({ "note_title": "Title", "folder_path": "Work/Clients", "account_identifier": "acct" }),
    )
    .expect("move");
  }

  #[test]
  fn delete_reminder_and_event_require_exactly_one_target() {
    let reminder = resolve_tool(TOOL_DELETE_REMINDER).expect("tool");
    let neither = validate_tool_arguments(reminder, &json!({})).expect_err("neither reminder");
    assert!(
      neither.contains("exactly one of calendar_item_identifier or reminder_title"),
      "{neither}"
    );
    let both = validate_tool_arguments(
      reminder,
      &json!({ "calendar_item_identifier": "r", "reminder_title": "Milk" }),
    )
    .expect_err("both reminders");
    assert!(
      both.contains("exactly one of calendar_item_identifier or reminder_title"),
      "{both}"
    );
    validate_tool_arguments(
      reminder,
      &json!({ "reminder_title": "Milk", "calendar_identifier": "list" }),
    )
    .expect("title");

    let event = resolve_tool(TOOL_DELETE_EVENT).expect("tool");
    let missing = validate_tool_arguments(event, &json!({})).expect_err("neither event");
    assert!(
      missing.contains("exactly one of event_identifier or event_title"),
      "{missing}"
    );
    validate_tool_arguments(
      event,
      &json!({
        "event_title": "Standup",
        "occurrence_date": "2026-10-26",
        "span": "future_events"
      }),
    )
    .expect("title");
    let bad_span =
      validate_tool_arguments(event, &json!({ "event_identifier": "e", "span": "all" })).expect_err("span");
    assert!(bad_span.contains("span"), "{bad_span}");
  }

  #[test]
  fn recurrence_day_of_the_week_is_a_weekday_name() {
    let tool = resolve_tool(TOOL_CREATE_EVENT).expect("tool");
    let base = json!({
      "calendar_identifier": "cal",
      "title": "Standup",
      "start_date": "2026-10-26T09:00:00-04:00",
      "end_date": "2026-10-26T09:30:00-04:00"
    });
    let mut named = base.clone();
    named["recurrence_rules"] = json!([{
      "frequency": "weekly",
      "days_of_the_week": [{ "day_of_the_week": "monday", "week_number": 1 }]
    }]);
    validate_tool_arguments(tool, &named).expect("weekday name");
    let mut numbered = base;
    numbered["recurrence_rules"] = json!([{
      "frequency": "weekly",
      "days_of_the_week": [{ "day_of_the_week": 2 }]
    }]);
    let err = validate_tool_arguments(tool, &numbered).expect_err("integer weekday");
    assert!(err.contains("day_of_the_week"), "{err}");
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

  #[test]
  fn timed_event_without_offset_or_zone_is_rejected() {
    let tool = resolve_tool(TOOL_CREATE_EVENT).expect("tool");
    let err = validate_tool_arguments(
      tool,
      &json!({
        "calendar_identifier": "c1",
        "title": "Standup",
        "start_date": "2026-10-19T09:00:00",
        "end_date": "2026-10-19T09:30:00"
      }),
    )
    .expect_err("naive");
    assert!(
      err.contains("offset") && err.contains("time_zone") && err.contains("server"),
      "{err}"
    );
  }

  #[test]
  fn timed_event_with_zone_or_offset_is_accepted() {
    let tool = resolve_tool(TOOL_CREATE_EVENT).expect("tool");
    validate_tool_arguments(
      tool,
      &json!({
        "calendar_identifier": "c1",
        "title": "Standup",
        "time_zone": "America/New_York",
        "start_date": "2026-10-19T09:00:00",
        "end_date": "2026-10-19T09:30:00"
      }),
    )
    .expect("zone");
    validate_tool_arguments(
      tool,
      &json!({
        "calendar_identifier": "c1",
        "title": "Standup",
        "start_date": "2026-10-19T13:00:00Z",
        "end_date": "2026-10-19T13:30:00Z"
      }),
    )
    .expect("offset");
  }

  #[test]
  fn all_day_date_only_stays_a_date_and_timed_date_only_does_not() {
    let tool = resolve_tool(TOOL_UPDATE_EVENT).expect("tool");
    validate_tool_arguments(
      tool,
      &json!({
        "event_identifier": "e1",
        "is_all_day": true,
        "start_date": "2026-10-19",
        "end_date": "2026-10-20"
      }),
    )
    .expect("all day");
    let err = validate_tool_arguments(
      tool,
      &json!({
        "event_identifier": "e1",
        "start_date": "2026-10-19",
        "end_date": "2026-10-20"
      }),
    )
    .expect_err("date only");
    assert!(err.contains("is_all_day") && err.contains("server"), "{err}");
  }

  #[test]
  fn unknown_event_zone_is_not_the_server_zone() {
    let tool = resolve_tool(TOOL_CREATE_EVENT).expect("tool");
    let err = validate_tool_arguments(
      tool,
      &json!({
        "calendar_identifier": "c1",
        "title": "Standup",
        "time_zone": "Not/A_Zone",
        "start_date": "2026-10-19T09:00:00",
        "end_date": "2026-10-19T09:30:00"
      }),
    )
    .expect_err("unknown zone");
    assert!(err.contains("IANA") && err.contains("server"), "{err}");
  }

  #[test]
  fn list_event_bounds_still_require_an_offset() {
    let tool = resolve_tool(TOOL_LIST_EVENTS).expect("tool");
    let err = validate_tool_arguments(
      tool,
      &json!({
        "start_date": "2026-10-19T09:00:00",
        "end_date": "2026-10-19T10:00:00Z"
      }),
    )
    .expect_err("naive bound");
    assert!(err.contains("numeric offset") && err.contains("server"), "{err}");
  }

  #[test]
  fn floating_reminder_due_time_is_accepted_without_a_zone() {
    let tool = resolve_tool(TOOL_CREATE_REMINDER).expect("tool");
    validate_tool_arguments(
      tool,
      &json!({
        "calendar_identifier": "c1",
        "title": "Pay",
        "due_date_components": { "year": 2026, "month": 10, "day": 19, "hour": 9, "minute": 0 }
      }),
    )
    .expect("floating due");
  }

  #[test]
  fn malformed_event_dates_do_not_panic() {
    let tool = resolve_tool(TOOL_CREATE_EVENT).expect("tool");
    let rejected = [
      ("2026-10-19T09:00:00+a€", false),
      ("2026-10-19T09:00:00+1€", false),
      ("2026-02-31T09:00:00Z", false),
      ("2026-02-31", true),
      ("2025-02-29", true),
      ("2026-04-31", true),
    ];
    for (start, all_day) in rejected {
      let err = validate_tool_arguments(
        tool,
        &json!({
          "calendar_identifier": "c1",
          "title": "Standup",
          "time_zone": "America/New_York",
          "is_all_day": all_day,
          "start_date": start,
          "end_date": "2026-10-19T10:00:00-04:00"
        }),
      )
      .expect_err(start);
      assert!(err.contains("start_date"), "{start}: {err}");
    }
  }

  #[test]
  fn dst_gap_and_fold_name_the_problem() {
    let tool = resolve_tool(TOOL_CREATE_EVENT).expect("tool");
    let gap = validate_tool_arguments(
      tool,
      &json!({
        "calendar_identifier": "c1",
        "title": "Standup",
        "time_zone": "America/New_York",
        "start_date": "2026-03-08T02:30:00",
        "end_date": "2026-03-08T03:30:00"
      }),
    )
    .expect_err("gap");
    assert!(
      gap.contains("gap") && gap.contains("2026-03-08T02:30:00") && gap.contains("America/New_York"),
      "{gap}"
    );

    let fold = validate_tool_arguments(
      tool,
      &json!({
        "calendar_identifier": "c1",
        "title": "Standup",
        "time_zone": "America/New_York",
        "start_date": "2026-11-01T01:30:00",
        "end_date": "2026-11-01T02:30:00"
      }),
    )
    .expect_err("fold");
    assert!(
      fold.contains("explicit offset") && fold.contains("2026-11-01T01:30:00"),
      "{fold}"
    );

    let later = validate_tool_arguments(
      tool,
      &json!({
        "calendar_identifier": "c1",
        "title": "Later",
        "time_zone": "America/New_York",
        "start_date": "2027-03-14T02:30:00",
        "end_date": "2027-03-14T03:30:00"
      }),
    )
    .expect_err("2027 gap");
    assert!(
      later.contains("gap") && later.contains("2027-03-14T02:30:00"),
      "{later}"
    );
  }

  #[test]
  fn exclusive_minimum_rejects_the_bound_and_accepts_above_it() {
    let tool = resolve_tool(TOOL_RECOGNIZE_DOCUMENTS).expect("tool");
    let with_width = |width: f64| {
      json!({
        "image_path": "/tmp/scan.png",
        "region_of_interest": {
          "origin": { "x": 0.0, "y": 0.0 },
          "size": { "width": width, "height": 0.5 }
        }
      })
    };
    let zero = validate_tool_arguments(tool, &with_width(0.0)).expect_err("zero width");
    assert!(
      zero.contains("region_of_interest.size.width") && zero.contains("greater than 0"),
      "{zero}"
    );
    validate_tool_arguments(tool, &with_width(0.25)).expect("positive width");
  }

  #[test]
  fn calculate_route_waypoints_need_a_location_and_at_most_eight() {
    let tool = resolve_tool(TOOL_CALCULATE_ROUTE).expect("tool");
    let stop = json!({ "coordinate": { "latitude": 28.8, "longitude": -82.0 } });
    let with_waypoints = |waypoints: serde_json::Value| {
      json!({
        "source": { "coordinate": { "latitude": 28.8, "longitude": -81.6 } },
        "destination": { "identifier": "I-TAMPA" },
        "waypoints": waypoints
      })
    };
    validate_tool_arguments(tool, &with_waypoints(json!([stop, { "identifier": "I-STOP" }]))).expect("valid");
    let named_only =
      validate_tool_arguments(tool, &with_waypoints(json!([stop, { "name": "Wildwood" }]))).expect_err("name only");
    assert!(named_only.contains("waypoints[1]"), "{named_only}");
    let too_many = validate_tool_arguments(tool, &with_waypoints(json!(vec![stop; 9]))).expect_err("nine");
    assert!(too_many.contains("waypoints") && too_many.contains("8"), "{too_many}");
  }

  #[test]
  fn search_nearby_needs_exactly_one_anchor() {
    let tool = resolve_tool(crate::tools::TOOL_SEARCH_NEARBY).expect("tool");
    let coordinate = json!({ "latitude": 28.8, "longitude": -81.6 });
    let neither = validate_tool_arguments(tool, &json!({ "radius_meters": 500 })).expect_err("neither");
    assert!(
      neither.contains("coordinate") && neither.contains("region"),
      "{neither}"
    );
    let both = validate_tool_arguments(
      tool,
      &json!({ "coordinate": coordinate, "region": { "center": coordinate } }),
    )
    .expect_err("both");
    assert!(both.contains("exactly one"), "{both}");
    validate_tool_arguments(tool, &json!({ "coordinate": coordinate })).expect("coordinate");
    validate_tool_arguments(tool, &json!({ "region": { "center": coordinate } })).expect("region");
  }

  #[test]
  fn calculate_route_rejects_both_dates_like_travel_time() {
    let tool = resolve_tool(TOOL_CALCULATE_ROUTE).expect("tool");
    let endpoint = json!({ "coordinate": { "latitude": 28.8, "longitude": -81.6 } });
    let both = validate_tool_arguments(
      tool,
      &json!({
        "source": endpoint,
        "destination": endpoint,
        "departure_date": "2026-10-21T08:00:00-04:00",
        "arrival_date": "2026-10-21T10:00:00-04:00"
      }),
    )
    .expect_err("both dates");
    assert!(both.contains("exactly one of departure_date or arrival_date"), "{both}");
  }

  #[test]
  fn recurrence_occurrence_count_must_be_at_least_one() {
    let tool = resolve_tool(crate::tools::TOOL_SET_REMINDER_RECURRENCE).expect("tool");
    let rule = |count: i64| {
      json!({
        "calendar_item_identifier": "r1",
        "recurrence_rules": [{ "frequency": "daily", "interval": 1, "recurrence_end": { "occurrence_count": count } }]
      })
    };
    let zero = validate_tool_arguments(tool, &rule(0)).expect_err("zero");
    assert!(zero.contains("occurrence_count"), "{zero}");
    validate_tool_arguments(tool, &rule(3)).expect("three");
  }
}

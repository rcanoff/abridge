//! Typed / normalized tool arguments for high-traffic EventKit create/update tools (Phase C).
//!
//! After JSON Schema validation, selected tools deserialize into typed structs and
//! re-serialize for the Swift bridge. This keeps the FFI JSON contract while moving
//! structure ownership to Rust. Unknown tools pass arguments through unchanged.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::tools::{self, ToolDefinition};

/// Normalize arguments for tools that have a typed path. On success returns JSON to
/// forward to `ProviderBridge`. On type failure returns an error message.
pub fn normalize_tool_arguments(tool: &ToolDefinition, arguments: Value) -> Result<Value, String> {
  match tool.name {
    tools::TOOL_CREATE_REMINDER => normalize_typed::<CreateReminderArgs>(arguments, "create_reminder"),
    tools::TOOL_CREATE_EVENT => {
      let mut value = normalize_typed::<CreateEventArgs>(arguments, "create_event")?;
      anchor_event_dates(&mut value)?;
      Ok(value)
    }
    tools::TOOL_UPDATE_REMINDER => normalize_typed::<UpdateReminderArgs>(arguments, "update_reminder"),
    tools::TOOL_UPDATE_EVENT => {
      let mut value = normalize_typed::<UpdateEventArgs>(arguments, "update_event")?;
      anchor_event_dates(&mut value)?;
      Ok(value)
    }
    tools::TOOL_CREATE_CONTACT => normalize_typed::<CreateContactArgs>(arguments, "create_contact"),
    tools::TOOL_UPDATE_CONTACT => normalize_typed::<UpdateContactArgs>(arguments, "update_contact"),
    tools::TOOL_CALCULATE_ROUTE => normalize_typed::<CalculateRouteArgs>(arguments, "calculate_route"),
    tools::TOOL_FORWARD_GEOCODE => {
      let mut value = normalize_typed::<ForwardGeocodeArgs>(arguments, "forward_geocode")?;
      fill_region_span(&mut value);
      Ok(value)
    }
    tools::TOOL_SEARCH_PLACES => {
      let mut value = arguments;
      fill_region_span(&mut value);
      Ok(value)
    }
    tools::TOOL_SEARCH_NEARBY => {
      let mut value = arguments;
      fill_region_span(&mut value);
      fill_nearby_radius(&mut value);
      Ok(value)
    }
    _ => Ok(arguments),
  }
}

/// Span used for an omitted `region.span` or a 0 delta: 0.1° is about 11 km of latitude.
const DEFAULT_REGION_SPAN_DEGREES: f64 = 0.1;

/// Size around `search_nearby`'s coordinate when `radius_meters` is omitted, null, or 0.
const DEFAULT_NEARBY_RADIUS_METERS: f64 = 1000.0;

fn fill_nearby_radius(value: &mut Value) {
  let Some(object) = value.as_object_mut() else {
    return;
  };
  if object.get("coordinate").is_none_or(Value::is_null) {
    return;
  }
  let radius = object.get("radius_meters").and_then(Value::as_f64);
  if radius.is_none_or(|radius| radius == 0.0) {
    object.insert("radius_meters".into(), Value::from(DEFAULT_NEARBY_RADIUS_METERS));
  }
}

/// MapKit needs a positive span. Clients often send only a center, or a 0 span, so fill each
/// missing or 0 delta with the default before Swift.
fn fill_region_span(value: &mut Value) {
  let Some(region) = value.get_mut("region").and_then(Value::as_object_mut) else {
    return;
  };
  let span = region
    .entry("span")
    .or_insert_with(|| Value::Object(serde_json::Map::new()));
  let Some(span) = span.as_object_mut() else {
    return;
  };
  for key in ["latitude_delta", "longitude_delta"] {
    let delta = span.get(key).and_then(Value::as_f64);
    if delta.is_none_or(|delta| delta == 0.0) {
      span.insert(key.to_string(), Value::from(DEFAULT_REGION_SPAN_DEGREES));
    }
  }
}

/// Rewrite event dates into instants before Swift. A wall time uses the given `time_zone`.
/// An all-day calendar date becomes local midnight in that zone, or the server Mac's zone when
/// the event has none, so the day read back is the day that was written.
fn anchor_event_dates(value: &mut Value) -> Result<(), String> {
  let zone = value
    .get("time_zone")
    .and_then(Value::as_str)
    .filter(|zone| !zone.is_empty())
    .map(str::to_string);
  let all_day = value.get("is_all_day").and_then(Value::as_bool) == Some(true);
  let Some(object) = value.as_object_mut() else {
    return Ok(());
  };
  for key in ["start_date", "end_date"] {
    let Some(text) = object.get(key).and_then(Value::as_str).map(str::to_string) else {
      continue;
    };
    if let Some(anchored) = crate::datetime::normalize_event_date(key, &text, all_day, zone.as_deref())? {
      object.insert(key.to_string(), Value::String(anchored));
    }
  }
  Ok(())
}

fn normalize_typed<T>(arguments: Value, label: &str) -> Result<Value, String>
where
  T: for<'de> Deserialize<'de> + Serialize,
{
  let typed: T = serde_json::from_value(arguments).map_err(|err| format!("typed {label} args: {err}"))?;
  serde_json::to_value(typed).map_err(|err| format!("serialize {label} args: {err}"))
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct CreateReminderArgs {
  calendar_identifier: String,
  title: String,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  notes: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  location: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  url: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  priority: Option<i64>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  due_date_components: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  start_date_components: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  time_zone: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  is_completed: Option<bool>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  completion_date: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  alarms: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  recurrence_rules: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct CreateEventArgs {
  calendar_identifier: String,
  title: String,
  start_date: String,
  end_date: String,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  notes: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  location: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  url: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  time_zone: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  is_all_day: Option<bool>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  availability: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  structured_location: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  alarms: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  recurrence_rules: Option<Value>,
}

/// Update payloads keep nested/optional JSON as `Value` so null vs omit is preserved.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct UpdateReminderArgs {
  calendar_item_identifier: String,
  #[serde(flatten)]
  rest: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct UpdateEventArgs {
  event_identifier: String,
  #[serde(flatten)]
  rest: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct CreateContactArgs {
  #[serde(default, skip_serializing_if = "Option::is_none")]
  container_identifier: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  contact_type: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  given_name: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  family_name: Option<String>,
  #[serde(flatten)]
  rest: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct UpdateContactArgs {
  contact_identifier: String,
  #[serde(flatten)]
  rest: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct CalculateRouteArgs {
  source: Value,
  destination: Value,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  transport_type: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  requests_alternate_routes: Option<bool>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  departure_date: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  arrival_date: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  toll_preference: Option<String>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  highway_preference: Option<String>,
  /// Rust routes each leg separately; `route_legs` strips this before Swift.
  #[serde(default, skip_serializing_if = "Option::is_none")]
  waypoints: Option<Vec<Value>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct ForwardGeocodeArgs {
  address: String,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  region: Option<Value>,
  #[serde(default, skip_serializing_if = "Option::is_none")]
  preferred_locale: Option<String>,
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::tools::resolve_tool;
  use serde_json::json;

  #[test]
  fn create_reminder_round_trips_required_fields() {
    let tool = resolve_tool(tools::TOOL_CREATE_REMINDER).expect("tool");
    let input = json!({
      "calendar_identifier": "list-1",
      "title": "Buy milk",
      "priority": 5
    });
    let out = normalize_tool_arguments(tool, input).expect("ok");
    assert_eq!(out["calendar_identifier"], "list-1");
    assert_eq!(out["title"], "Buy milk");
    assert_eq!(out["priority"], 5);
  }

  #[test]
  fn create_event_round_trips_required_fields() {
    let tool = resolve_tool(tools::TOOL_CREATE_EVENT).expect("tool");
    let input = json!({
      "calendar_identifier": "cal-1",
      "title": "Meeting",
      "start_date": "2024-01-15T12:00:00Z",
      "end_date": "2024-01-15T13:00:00Z"
    });
    let out = normalize_tool_arguments(tool, input).expect("ok");
    assert_eq!(out["title"], "Meeting");
    assert_eq!(out["start_date"], "2024-01-15T12:00:00Z");
  }

  #[test]
  fn update_event_requires_event_identifier() {
    let tool = resolve_tool(tools::TOOL_UPDATE_EVENT).expect("tool");
    let out = normalize_tool_arguments(
      tool,
      json!({
        "event_identifier": "evt-1",
        "title": "Renamed"
      }),
    )
    .expect("ok");
    assert_eq!(out["event_identifier"], "evt-1");
    assert_eq!(out["title"], "Renamed");
  }

  #[test]
  fn untyped_tools_pass_through() {
    let tool = resolve_tool(tools::TOOL_LIST_LISTS).expect("tool");
    let input = json!({});
    let out = normalize_tool_arguments(tool, input.clone()).expect("ok");
    assert_eq!(out, input);
  }

  #[test]
  fn create_contact_round_trips_container() {
    let tool = resolve_tool(tools::TOOL_CREATE_CONTACT).expect("tool");
    let out = normalize_tool_arguments(
      tool,
      json!({
        "container_identifier": "default",
        "given_name": "Ada"
      }),
    )
    .expect("ok");
    assert_eq!(out["container_identifier"], "default");
    assert_eq!(out["given_name"], "Ada");
  }

  #[test]
  fn create_contact_omits_container_and_keeps_read_shaped_phone() {
    let tool = resolve_tool(tools::TOOL_CREATE_CONTACT).expect("tool");
    let out = normalize_tool_arguments(
      tool,
      json!({
        "given_name": "Ada",
        "phone_numbers": [{ "label": "mobile", "identifier": "p1", "value": "555-0100" }],
        "email_addresses": [{ "label": "work", "value": "ada@example.com" }],
        "postal_addresses": [{ "label": "home", "value": { "street": "1 Main", "city": "Town" } }]
      }),
    )
    .expect("ok");
    assert!(out.get("container_identifier").is_none());
    assert_eq!(out["phone_numbers"][0]["value"], "555-0100");
    assert_eq!(out["phone_numbers"][0]["label"], "mobile");
    assert_eq!(out["email_addresses"][0]["value"], "ada@example.com");
    assert_eq!(out["postal_addresses"][0]["value"]["street"], "1 Main");
  }

  #[test]
  fn calculate_route_requires_source_and_destination() {
    let tool = resolve_tool(tools::TOOL_CALCULATE_ROUTE).expect("tool");
    let out = normalize_tool_arguments(
      tool,
      json!({
        "source": { "coordinate": { "latitude": 1.0, "longitude": 2.0 } },
        "destination": { "coordinate": { "latitude": 3.0, "longitude": 4.0 } }
      }),
    )
    .expect("ok");
    assert!(out.get("source").is_some());
    assert!(out.get("destination").is_some());
  }

  #[test]
  fn calculate_route_keeps_route_preferences_and_waypoints() {
    let tool = resolve_tool(tools::TOOL_CALCULATE_ROUTE).expect("tool");
    let waypoints = json!([{ "coordinate": { "latitude": 28.9, "longitude": -82.0 } }]);
    let out = normalize_tool_arguments(
      tool,
      json!({
        "source": { "coordinate": { "latitude": 1.0, "longitude": 2.0 } },
        "destination": { "coordinate": { "latitude": 3.0, "longitude": 4.0 } },
        "waypoints": waypoints,
        "toll_preference": "avoid",
        "highway_preference": "avoid"
      }),
    )
    .expect("ok");
    assert_eq!(out["toll_preference"], "avoid");
    assert_eq!(out["highway_preference"], "avoid");
    assert_eq!(out["waypoints"], waypoints);
  }

  #[test]
  fn create_reminder_typed_path_rejects_wrong_priority_type() {
    let tool = resolve_tool(tools::TOOL_CREATE_REMINDER).expect("tool");
    let err = normalize_tool_arguments(
      tool,
      json!({
        "calendar_identifier": "list-1",
        "title": "X",
        "priority": true
      }),
    )
    .expect_err("type");
    assert!(err.contains("typed create_reminder"), "{err}");
  }

  #[test]
  fn create_event_wall_time_uses_the_given_zone() {
    let tool = resolve_tool(tools::TOOL_CREATE_EVENT).expect("tool");
    let out = normalize_tool_arguments(
      tool,
      json!({
        "calendar_identifier": "cal-1",
        "title": "Standup",
        "time_zone": "America/New_York",
        "start_date": "2026-10-19T09:00:00",
        "end_date": "2026-01-15T09:00"
      }),
    )
    .expect("ok");
    assert_eq!(out["start_date"], "2026-10-19T09:00:00-04:00");
    assert_eq!(out["end_date"], "2026-01-15T09:00:00-05:00");
    assert_eq!(out["time_zone"], "America/New_York");
  }

  #[test]
  fn create_event_all_day_date_stays_that_calendar_day() {
    let tool = resolve_tool(tools::TOOL_CREATE_EVENT).expect("tool");
    let out = normalize_tool_arguments(
      tool,
      json!({
        "calendar_identifier": "cal-1",
        "title": "Off",
        "is_all_day": true,
        "start_date": "2026-10-19",
        "end_date": "2026-10-20"
      }),
    )
    .expect("ok");
    assert_eq!(out["start_date"], "2026-10-19T00:00:00Z");
    assert_eq!(out["end_date"], "2026-10-20T00:00:00Z");
  }

  #[test]
  fn create_event_all_day_in_new_york_is_local_midnight() {
    let tool = resolve_tool(tools::TOOL_CREATE_EVENT).expect("tool");
    let out = normalize_tool_arguments(
      tool,
      json!({
        "calendar_identifier": "cal-1",
        "title": "Off",
        "is_all_day": true,
        "time_zone": "America/New_York",
        "start_date": "2026-10-19",
        "end_date": "2026-10-20"
      }),
    )
    .expect("ok");
    assert_eq!(out["start_date"], "2026-10-19T04:00:00Z");
    assert_eq!(out["end_date"], "2026-10-20T04:00:00Z");
  }

  #[test]
  fn create_event_future_summer_keeps_daylight_time() {
    let tool = resolve_tool(tools::TOOL_CREATE_EVENT).expect("tool");
    let out = normalize_tool_arguments(
      tool,
      json!({
        "calendar_identifier": "cal-1",
        "title": "Later",
        "time_zone": "America/New_York",
        "start_date": "2100-07-15T12:00:00",
        "end_date": "2100-07-15T13:00:00"
      }),
    )
    .expect("ok");
    assert_eq!(out["start_date"], "2100-07-15T12:00:00-04:00");
    assert_eq!(out["end_date"], "2100-07-15T13:00:00-04:00");
  }

  #[test]
  fn create_event_rejects_a_dst_gap() {
    let tool = resolve_tool(tools::TOOL_CREATE_EVENT).expect("tool");
    let err = normalize_tool_arguments(
      tool,
      json!({
        "calendar_identifier": "cal-1",
        "title": "Gap",
        "time_zone": "America/New_York",
        "start_date": "2026-03-08T02:30:00",
        "end_date": "2026-03-08T03:30:00"
      }),
    )
    .expect_err("gap");
    assert!(err.contains("gap") && err.contains("2026-03-08T02:30:00"), "{err}");
  }

  #[test]
  fn create_reminder_due_without_zone_stays_without_zone() {
    let tool = resolve_tool(tools::TOOL_CREATE_REMINDER).expect("tool");
    let out = normalize_tool_arguments(
      tool,
      json!({
        "calendar_identifier": "list-1",
        "title": "Pay",
        "time_zone": "America/New_York",
        "due_date_components": { "year": 2026, "month": 10, "day": 19, "hour": 9, "minute": 0 }
      }),
    )
    .expect("ok");
    assert!(out["due_date_components"].get("time_zone").is_none());
    assert_eq!(out["due_date_components"]["hour"], 9);
    assert_eq!(out["time_zone"], "America/New_York");
  }

  #[test]
  fn region_zero_or_missing_span_uses_default_and_keeps_a_given_delta() {
    let center = json!({ "latitude": 28.8, "longitude": -81.6 });
    for name in [tools::TOOL_SEARCH_PLACES, tools::TOOL_SEARCH_NEARBY] {
      let tool = resolve_tool(name).expect("tool");
      let zero = json!({
        "query": "Publix",
        "region": { "center": center, "span": { "latitude_delta": 0, "longitude_delta": 0.0 } }
      });
      crate::arg_validation::validate_tool_arguments(tool, &zero).expect("zero span is valid");
      let out = normalize_tool_arguments(tool, zero).expect("ok");
      assert_eq!(
        out["region"]["span"],
        json!({ "latitude_delta": 0.1, "longitude_delta": 0.1 }),
        "{name}"
      );

      let partial = json!({ "region": { "center": center, "span": { "latitude_delta": 0.5 } } });
      let out = normalize_tool_arguments(tool, partial).expect("ok");
      assert_eq!(
        out["region"]["span"],
        json!({ "latitude_delta": 0.5, "longitude_delta": 0.1 }),
        "{name}"
      );
    }

    let geocode = resolve_tool(tools::TOOL_FORWARD_GEOCODE).expect("tool");
    let center_only = json!({ "address": "1 Main St", "region": { "center": center } });
    crate::arg_validation::validate_tool_arguments(geocode, &center_only).expect("center only is valid");
    let out = normalize_tool_arguments(geocode, center_only).expect("ok");
    assert_eq!(
      out["region"]["span"],
      json!({ "latitude_delta": 0.1, "longitude_delta": 0.1 })
    );
    assert_eq!(out["region"]["center"], center);
  }

  #[test]
  fn region_negative_span_is_rejected() {
    let tool = resolve_tool(tools::TOOL_SEARCH_PLACES).expect("tool");
    let err = crate::arg_validation::validate_tool_arguments(
      tool,
      &json!({
        "query": "Publix",
        "region": {
          "center": { "latitude": 28.8, "longitude": -81.6 },
          "span": { "latitude_delta": -1, "longitude_delta": 0.1 }
        }
      }),
    )
    .expect_err("negative");
    assert!(err.contains("region.span.latitude_delta"), "{err}");
  }

  #[test]
  fn nearby_radius_zero_or_missing_uses_default_and_keeps_a_given_radius() {
    let tool = resolve_tool(tools::TOOL_SEARCH_NEARBY).expect("tool");
    let coordinate = json!({ "latitude": 28.8, "longitude": -81.6 });
    let zero = json!({ "coordinate": coordinate, "radius_meters": 0 });
    crate::arg_validation::validate_tool_arguments(tool, &zero).expect("zero radius is valid");
    for input in [zero, json!({ "coordinate": coordinate })] {
      let out = normalize_tool_arguments(tool, input).expect("ok");
      assert_eq!(out["radius_meters"], json!(1000.0));
    }
    let given = normalize_tool_arguments(tool, json!({ "coordinate": coordinate, "radius_meters": 500 })).expect("ok");
    assert_eq!(given["radius_meters"], json!(500));

    let region_only = normalize_tool_arguments(tool, json!({ "region": { "center": coordinate } })).expect("ok");
    assert!(region_only.get("radius_meters").is_none());

    let negative =
      crate::arg_validation::validate_tool_arguments(tool, &json!({ "coordinate": coordinate, "radius_meters": -5 }))
        .expect_err("negative");
    assert!(negative.contains("radius_meters"), "{negative}");
  }
}

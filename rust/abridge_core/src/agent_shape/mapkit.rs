//! MapKit shapes. Search rows are a place an agent can open; routes keep the steps, not the polyline.

use serde_json::{Map, Value};

use super::util::{self, copy_number, copy_text, copy_true};

pub(crate) fn search_response(value: &Value) -> Value {
  let mut object = Map::new();
  if let Some(items) = value.get("map_items").and_then(Value::as_array) {
    object.insert("map_items".into(), Value::Array(items.iter().map(summary).collect()));
  }
  if let Some(region) = value.get("bounding_region").and_then(util::slim) {
    object.insert("bounding_region".into(), region);
  }
  Value::Object(object)
}

pub(crate) fn summary(value: &Value) -> Value {
  let mut object = Map::new();
  if let Some(name) = util::text(value, "name").filter(|name| !is_placeholder_location_name(name)) {
    object.insert("name".into(), Value::String(name.to_string()));
  }
  copy_text(&mut object, value, "identifier");
  copy_text(&mut object, value, "phone_number");
  copy_text(&mut object, value, "url");
  copy_text(&mut object, value, "time_zone");
  copy_text(&mut object, value, "point_of_interest_category");
  copy_true(&mut object, value, "is_current_location");
  if let Some(coordinate) = coordinate(value) {
    object.insert("coordinate".into(), coordinate);
  }
  if let Some(address) = address_line(value) {
    object.insert("address".into(), Value::String(address));
  }
  Value::Object(object)
}

pub(crate) fn detail(value: &Value) -> Value {
  let mut object = match summary(value) {
    Value::Object(object) => object,
    other => return other,
  };
  if let Some(postal) = value.pointer("/placemark/postal_address").and_then(util::slim) {
    object.insert("postal_address".into(), postal);
  }
  if let Some(lines) = value.pointer("/address_representations/0").and_then(util::slim) {
    object.insert("address_representations".into(), lines);
  }
  Value::Object(object)
}

pub(crate) fn route_response(value: &Value, request: &Value) -> Value {
  let mut object = Map::new();
  if let Some(source) = value.get("source") {
    object.insert("source".into(), endpoint_summary(source, request.get("source")));
  }
  if let Some(destination) = value.get("destination") {
    object.insert(
      "destination".into(),
      endpoint_summary(destination, request.get("destination")),
    );
  }
  if let Some(routes) = value.get("routes").and_then(Value::as_array) {
    object.insert("routes".into(), Value::Array(routes.iter().map(route).collect()));
  }
  Value::Object(object)
}

pub(crate) fn travel_time(value: &Value, request: &Value) -> Value {
  let mut object = Map::new();
  if let Some(source) = value.get("source") {
    object.insert("source".into(), endpoint_summary(source, request.get("source")));
  }
  if let Some(destination) = value.get("destination") {
    object.insert(
      "destination".into(),
      endpoint_summary(destination, request.get("destination")),
    );
  }
  copy_number(&mut object, value, "expected_travel_time");
  copy_number(&mut object, value, "distance");
  copy_text(&mut object, value, "expected_arrival_date");
  copy_text(&mut object, value, "expected_departure_date");
  if let Some(transport) = value.get("transport_type").and_then(util::slim) {
    object.insert("transport_type".into(), transport);
  }
  Value::Object(object)
}

pub(crate) fn navigation(value: &Value, request: &Value) -> Value {
  let mut object = Map::new();
  copy_true(&mut object, value, "opened");
  if let Some(source) = value.get("source") {
    object.insert("source".into(), endpoint_summary(source, request.get("source")));
  }
  if let Some(destination) = value.get("destination") {
    object.insert(
      "destination".into(),
      endpoint_summary(destination, request.get("destination")),
    );
  }
  if let Some(transport) = value.get("transport_type").and_then(util::slim) {
    object.insert("transport_type".into(), transport);
  }
  if let Some(options) = value.get("launch_options").and_then(util::slim) {
    object.insert("launch_options".into(), options);
  }
  Value::Object(object)
}

fn endpoint_summary(response: &Value, request: Option<&Value>) -> Value {
  let mut object = match summary(response) {
    Value::Object(object) => object,
    other => return other,
  };
  if let Some(name) = request
    .and_then(|item| util::text(item, "name"))
    .filter(|name| !is_placeholder_location_name(name))
  {
    object.insert("name".into(), Value::String(name.to_string()));
  }
  if object.get("identifier").and_then(Value::as_str).is_none()
    && let Some(identifier) = request.and_then(|item| util::text(item, "identifier"))
  {
    object.insert("identifier".into(), Value::String(identifier.to_string()));
  }
  Value::Object(object)
}

fn is_placeholder_location_name(name: &str) -> bool {
  name.trim().eq_ignore_ascii_case("Unknown Location")
}

fn route(value: &Value) -> Value {
  let mut object = Map::new();
  copy_text(&mut object, value, "name");
  copy_number(&mut object, value, "distance");
  copy_number(&mut object, value, "expected_travel_time");
  copy_true(&mut object, value, "has_tolls");
  copy_true(&mut object, value, "has_highways");
  if let Some(notices) = value.get("advisory_notices").and_then(util::slim) {
    object.insert("advisory_notices".into(), notices);
  }
  if let Some(transport) = value.get("transport_type").and_then(util::slim) {
    object.insert("transport_type".into(), transport);
  }
  if let Some(steps) = value.get("steps").and_then(Value::as_array) {
    let steps: Vec<Value> = steps.iter().map(step).collect();
    if !steps.is_empty() {
      object.insert("steps".into(), Value::Array(steps));
    }
  }
  Value::Object(object)
}

fn step(value: &Value) -> Value {
  let mut object = Map::new();
  copy_text(&mut object, value, "instructions");
  copy_text(&mut object, value, "notice");
  copy_number(&mut object, value, "distance");
  if let Some(transport) = value.get("transport_type").and_then(util::slim) {
    object.insert("transport_type".into(), transport);
  }
  Value::Object(object)
}

fn coordinate(value: &Value) -> Option<Value> {
  let source = value
    .pointer("/location/coordinate")
    .or_else(|| value.pointer("/placemark/coordinate"))?;
  let mut object = Map::new();
  copy_number(&mut object, source, "latitude");
  copy_number(&mut object, source, "longitude");
  if object.len() == 2 {
    Some(Value::Object(object))
  } else {
    None
  }
}

fn address_line(value: &Value) -> Option<String> {
  line_at(value, "/address/full_address")
    .or_else(|| line_at(value, "/address/short_address"))
    .or_else(|| line_at(value, "/address_representations/0/full_address"))
    .or_else(|| line_at(value, "/address_representations/0/short_address"))
    .or_else(|| postal_line(value.pointer("/placemark/postal_address")))
}

fn line_at(value: &Value, pointer: &str) -> Option<String> {
  value
    .pointer(pointer)
    .and_then(Value::as_str)
    .filter(|text| !text.is_empty())
    .map(str::to_string)
}

fn postal_line(value: Option<&Value>) -> Option<String> {
  let address = value?;
  let parts: Vec<&str> = ["street", "city", "state", "postal_code", "country"]
    .into_iter()
    .filter_map(|key| address.get(key).and_then(Value::as_str).filter(|text| !text.is_empty()))
    .collect();
  if parts.is_empty() { None } else { Some(parts.join(", ")) }
}

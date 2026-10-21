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
  let mut object = place_fields(value);
  put_place_url(&mut object);
  Value::Object(object)
}

fn place_fields(value: &Value) -> Map<String, Value> {
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
  object
}

/// Apple Maps place link: the Place ID when MapKit has one, else the coordinate with the name
/// as the place card title.
fn put_place_url(object: &mut Map<String, Value>) {
  let url = if let Some(identifier) = object.get("identifier").and_then(Value::as_str) {
    format!("https://maps.apple.com/place?place-id={}", percent_encode(identifier))
  } else if let Some(coordinate) = object.get("coordinate").and_then(coordinate_text) {
    match object.get("name").and_then(Value::as_str) {
      Some(name) => format!(
        "https://maps.apple.com/place?coordinate={coordinate}&name={}",
        percent_encode(name)
      ),
      None => format!("https://maps.apple.com/place?coordinate={coordinate}"),
    }
  } else {
    return;
  };
  object.insert("maps_url".into(), Value::String(url));
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
  let source = value
    .get("source")
    .map(|source| endpoint_summary(source, request.get("source")));
  let destination = value
    .get("destination")
    .map(|destination| endpoint_summary(destination, request.get("destination")));
  let maps_url = source
    .as_ref()
    .zip(destination.as_ref())
    .and_then(|(source, destination)| directions_url(source, &[], destination, request));
  if let Some(source) = source {
    object.insert("source".into(), source);
  }
  if let Some(destination) = destination {
    object.insert("destination".into(), destination);
  }
  if let Some(routes) = value.get("routes").and_then(Value::as_array) {
    object.insert("routes".into(), Value::Array(routes.iter().map(route).collect()));
  }
  util::put_text(&mut object, "maps_url", maps_url.as_deref());
  Value::Object(object)
}

/// One route through `request.waypoints`, from one MapKit response per leg (in order). Each leg
/// uses that leg's first route; totals add the legs.
pub(crate) fn route_legs_response(legs: &[Value], request: &Value) -> Value {
  let (source, waypoints, destination) = leg_stops(legs, request);

  let mut distance = 0.0;
  let mut travel_time = 0.0;
  let mut has_tolls = false;
  let mut has_highways = false;
  let mut shaped_legs = Vec::with_capacity(legs.len());
  for leg in legs {
    let Some(first) = leg.pointer("/routes/0") else {
      continue;
    };
    distance += first.get("distance").and_then(Value::as_f64).unwrap_or(0.0);
    travel_time += first.get("expected_travel_time").and_then(Value::as_f64).unwrap_or(0.0);
    has_tolls |= first.get("has_tolls").and_then(Value::as_bool) == Some(true);
    has_highways |= first.get("has_highways").and_then(Value::as_bool) == Some(true);
    shaped_legs.push(route(first));
  }
  let mut combined = Map::new();
  combined.insert("distance".into(), Value::from(distance));
  combined.insert("expected_travel_time".into(), Value::from(travel_time));
  if has_tolls {
    combined.insert("has_tolls".into(), Value::Bool(true));
  }
  if has_highways {
    combined.insert("has_highways".into(), Value::Bool(true));
  }
  combined.insert("legs".into(), Value::Array(shaped_legs));

  let maps_url = source
    .as_ref()
    .zip(destination.as_ref())
    .and_then(|(source, destination)| directions_url(source, &waypoints, destination, request));
  let mut object = Map::new();
  if let Some(source) = source {
    object.insert("source".into(), source);
  }
  if let Some(destination) = destination {
    object.insert("destination".into(), destination);
  }
  if !waypoints.is_empty() {
    object.insert("waypoints".into(), Value::Array(waypoints));
  }
  object.insert("routes".into(), Value::Array(vec![Value::Object(combined)]));
  util::put_text(&mut object, "maps_url", maps_url.as_deref());
  Value::Object(object)
}

/// Apple Maps unified directions URL for shaped endpoints. Coordinates fix each stop; a MapKit
/// identifier is the Place ID Maps shows for that stop, and Maps prefers it over the coordinate.
/// Maps pairs `waypoint-place-id` with waypoints by position and ignores the IDs when their count
/// differs, so once any waypoint has one, each waypoint gets one (empty when it has none).
fn directions_url(source: &Value, waypoints: &[Value], destination: &Value, request: &Value) -> Option<String> {
  let mut query = vec![format!("source={}", coordinate_param(source)?)];
  if let Some(identifier) = util::text(source, "identifier") {
    query.push(format!("source-place-id={}", percent_encode(identifier)));
  }
  let waypoint_ids = waypoints
    .iter()
    .any(|waypoint| util::text(waypoint, "identifier").is_some());
  for waypoint in waypoints {
    query.push(format!("waypoint={}", coordinate_param(waypoint)?));
    if waypoint_ids {
      let identifier = util::text(waypoint, "identifier")
        .map(percent_encode)
        .unwrap_or_default();
      query.push(format!("waypoint-place-id={identifier}"));
    }
  }
  query.push(format!("destination={}", coordinate_param(destination)?));
  if let Some(identifier) = util::text(destination, "identifier") {
    query.push(format!("destination-place-id={}", percent_encode(identifier)));
  }
  // `any` lets Maps pick the mode; omitted or null is MapKit's automobile default.
  let mode = match util::text(request, "transport_type") {
    Some("walking") => Some("walking"),
    Some("transit") => Some("transit"),
    Some("cycling") => Some("cycling"),
    Some("any") => None,
    _ => Some("driving"),
  };
  if let Some(mode) = mode {
    query.push(format!("mode={mode}"));
  }
  let avoid: Vec<&str> = [("toll_preference", "tolls"), ("highway_preference", "highways")]
    .into_iter()
    .filter(|(key, _)| util::text(request, key) == Some("avoid"))
    .map(|(_, option)| option)
    .collect();
  if !avoid.is_empty() {
    query.push(format!("avoid={}", avoid.join(",")));
  }
  Some(format!("https://maps.apple.com/directions?{}", query.join("&")))
}

fn coordinate_param(endpoint: &Value) -> Option<String> {
  coordinate_text(endpoint.get("coordinate")?)
}

fn coordinate_text(coordinate: &Value) -> Option<String> {
  let latitude = coordinate.get("latitude").and_then(Value::as_f64)?;
  let longitude = coordinate.get("longitude").and_then(Value::as_f64)?;
  Some(format!("{latitude},{longitude}"))
}

fn percent_encode(text: &str) -> String {
  let mut encoded = String::with_capacity(text.len());
  for byte in text.bytes() {
    if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
      encoded.push(byte as char);
    } else {
      encoded.push_str(&format!("%{byte:02X}"));
    }
  }
  encoded
}

pub(crate) fn travel_time(value: &Value, request: &Value) -> Value {
  let mut object = Map::new();
  let source = value
    .get("source")
    .map(|source| endpoint_summary(source, request.get("source")));
  let destination = value
    .get("destination")
    .map(|destination| endpoint_summary(destination, request.get("destination")));
  let maps_url = source
    .as_ref()
    .zip(destination.as_ref())
    .and_then(|(source, destination)| directions_url(source, &[], destination, request));
  if let Some(source) = source {
    object.insert("source".into(), source);
  }
  if let Some(destination) = destination {
    object.insert("destination".into(), destination);
  }
  copy_number(&mut object, value, "expected_travel_time");
  copy_number(&mut object, value, "distance");
  copy_text(&mut object, value, "expected_arrival_date");
  copy_text(&mut object, value, "expected_departure_date");
  if let Some(transport) = value.get("transport_type").and_then(util::slim) {
    object.insert("transport_type".into(), transport);
  }
  util::put_text(&mut object, "maps_url", maps_url.as_deref());
  Value::Object(object)
}

/// Travel time through `request.waypoints`, from one MapKit estimate per leg (in order). The trip
/// departs when the first leg does and arrives when the last leg does.
pub(crate) fn travel_time_legs_response(legs: &[Value], request: &Value) -> Value {
  let (source, waypoints, destination) = leg_stops(legs, request);
  let mut travel_time = 0.0;
  let mut distance = 0.0;
  let mut shaped_legs = Vec::with_capacity(legs.len());
  for leg in legs {
    travel_time += leg.get("expected_travel_time").and_then(Value::as_f64).unwrap_or(0.0);
    distance += leg.get("distance").and_then(Value::as_f64).unwrap_or(0.0);
    let mut shaped = Map::new();
    copy_number(&mut shaped, leg, "expected_travel_time");
    copy_number(&mut shaped, leg, "distance");
    copy_text(&mut shaped, leg, "expected_departure_date");
    copy_text(&mut shaped, leg, "expected_arrival_date");
    shaped_legs.push(Value::Object(shaped));
  }
  let maps_url = source
    .as_ref()
    .zip(destination.as_ref())
    .and_then(|(source, destination)| directions_url(source, &waypoints, destination, request));
  let mut object = Map::new();
  if let Some(source) = source {
    object.insert("source".into(), source);
  }
  if let Some(destination) = destination {
    object.insert("destination".into(), destination);
  }
  if !waypoints.is_empty() {
    object.insert("waypoints".into(), Value::Array(waypoints));
  }
  object.insert("expected_travel_time".into(), Value::from(travel_time));
  object.insert("distance".into(), Value::from(distance));
  if let Some(first) = legs.first() {
    copy_text(&mut object, first, "expected_departure_date");
    if let Some(transport) = first.get("transport_type").and_then(util::slim) {
      object.insert("transport_type".into(), transport);
    }
  }
  if let Some(last) = legs.last() {
    copy_text(&mut object, last, "expected_arrival_date");
  }
  object.insert("legs".into(), Value::Array(shaped_legs));
  util::put_text(&mut object, "maps_url", maps_url.as_deref());
  Value::Object(object)
}

/// A stop as the caller sent it: its name, identifier, and coordinate, plus its place link.
pub(crate) fn request_endpoint(request: &Value) -> Value {
  let mut object = Map::new();
  if let Some(name) = util::text(request, "name").filter(|name| !is_placeholder_location_name(name)) {
    object.insert("name".into(), Value::String(name.to_string()));
  }
  copy_text(&mut object, request, "identifier");
  if let Some(coordinate) = request
    .get("coordinate")
    .filter(|coordinate| coordinate_text(coordinate).is_some())
  {
    let mut point = Map::new();
    copy_number(&mut point, coordinate, "latitude");
    copy_number(&mut point, coordinate, "longitude");
    object.insert("coordinate".into(), Value::Object(point));
  }
  put_place_url(&mut object);
  Value::Object(object)
}

/// A stop resolved from its MapKit identifier, labeled with what the caller sent.
pub(crate) fn resolved_endpoint(place: &Value, request: &Value) -> Value {
  endpoint_summary(place, Some(request))
}

/// `stops` are shaped source, waypoints, then destination.
pub(crate) fn navigation_url(stops: &[Value], request: &Value) -> Option<String> {
  let (source, rest) = stops.split_first()?;
  let (destination, waypoints) = rest.split_last()?;
  directions_url(source, waypoints, destination, request)
}

pub(crate) fn navigation_response(stops: &[Value], maps_url: &str, opened: bool) -> Value {
  let mut object = Map::new();
  if opened {
    object.insert("opened".into(), Value::Bool(true));
  }
  if let Some((source, rest)) = stops.split_first() {
    object.insert("source".into(), source.clone());
    if let Some((destination, waypoints)) = rest.split_last() {
      object.insert("destination".into(), destination.clone());
      if !waypoints.is_empty() {
        object.insert("waypoints".into(), Value::Array(waypoints.to_vec()));
      }
    }
  }
  object.insert("maps_url".into(), Value::String(maps_url.to_string()));
  Value::Object(object)
}

/// Shaped source, stops between legs, and destination for per-leg responses.
fn leg_stops(legs: &[Value], request: &Value) -> (Option<Value>, Vec<Value>, Option<Value>) {
  let waypoint_requests = request.get("waypoints").and_then(Value::as_array);
  let source = legs
    .first()
    .and_then(|leg| leg.get("source"))
    .map(|source| endpoint_summary(source, request.get("source")));
  let destination = legs
    .last()
    .and_then(|leg| leg.get("destination"))
    .map(|destination| endpoint_summary(destination, request.get("destination")));
  let waypoints = legs
    .iter()
    .take(legs.len().saturating_sub(1))
    .enumerate()
    .filter_map(|(index, leg)| {
      let stop = leg.get("destination")?;
      Some(endpoint_summary(
        stop,
        waypoint_requests.and_then(|items| items.get(index)),
      ))
    })
    .collect();
  (source, waypoints, destination)
}

/// The identifier is the one MapKit returned. Swift falls back to the coordinate when an
/// identifier lookup fails, so the caller's identifier is not echoed: Maps prefers a Place ID over
/// the coordinate and would open the place that failed.
fn endpoint_summary(response: &Value, request: Option<&Value>) -> Value {
  let mut object = place_fields(response);
  if let Some(name) = request
    .and_then(|item| util::text(item, "name"))
    .filter(|name| !is_placeholder_location_name(name))
  {
    object.insert("name".into(), Value::String(name.to_string()));
  }
  put_place_url(&mut object);
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

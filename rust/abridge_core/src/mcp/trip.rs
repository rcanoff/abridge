//! Trips through MapKit, which routes one source to one destination. With waypoints, Rust asks
//! Swift for each leg in order and combines the legs: a departure time moves forward by each leg's
//! travel time; an arrival time is routed from the last leg backward. Open navigation builds an
//! Apple Maps directions URL through every stop and has Swift open it.

use serde_json::{Map, Value, json};

use crate::agent_shape;
use crate::config::ProviderRequest;
use crate::datetime;
use crate::providers::ProviderBridge;

/// Keys that describe the whole trip, not one leg.
const TRIP_KEYS: [&str; 6] = [
  "source",
  "destination",
  "waypoints",
  "departure_date",
  "arrival_date",
  "requests_alternate_routes",
];

#[derive(Clone, Copy)]
pub(super) enum LegKind {
  /// `mapkit_calculate_route`: each leg uses its first route.
  Route,
  /// `mapkit_estimate_travel_time`.
  TravelTime,
}

impl LegKind {
  fn operation(self) -> &'static str {
    match self {
      Self::Route => "calculate_route",
      Self::TravelTime => "estimate_travel_time",
    }
  }

  fn seconds_pointer(self) -> &'static str {
    match self {
      Self::Route => "/routes/0/expected_travel_time",
      Self::TravelTime => "/expected_travel_time",
    }
  }
}

enum LegTime {
  Departure(i64),
  Arrival(i64),
}

/// `Ok` is the shaped response. `Err` is the error JSON to return to the caller.
pub(super) fn legs(kind: LegKind, arguments: &Value, provider: &dyn ProviderBridge) -> Result<Value, String> {
  let stops = stops(arguments);
  let leg_count = stops.len() - 1;
  let mut shared = Map::new();
  if let Some(object) = arguments.as_object() {
    for (key, value) in object {
      if !TRIP_KEYS.contains(&key.as_str()) {
        shared.insert(key.clone(), value.clone());
      }
    }
  }

  // Without a date the trip leaves now (this Mac's clock, as MapKit would use), so each later leg
  // still leaves when the one before it arrives.
  let mut time = match (
    text_unix(arguments, "departure_date"),
    text_unix(arguments, "arrival_date"),
  ) {
    (Some(departure), _) => LegTime::Departure(departure),
    (None, Some(arrival)) => LegTime::Arrival(arrival),
    (None, None) => LegTime::Departure(jiff::Timestamp::now().as_second()),
  };
  let order: Vec<usize> = if matches!(time, LegTime::Arrival(_)) {
    (0..leg_count).rev().collect()
  } else {
    (0..leg_count).collect()
  };

  let mut legs: Vec<Value> = vec![Value::Null; leg_count];
  for index in order {
    let mut payload = shared.clone();
    payload.insert("source".into(), stops[index].clone());
    payload.insert("destination".into(), stops[index + 1].clone());
    match time {
      LegTime::Departure(unix) => {
        payload.insert("departure_date".into(), Value::String(datetime::format_unix_utc(unix)));
      }
      LegTime::Arrival(unix) => {
        payload.insert("arrival_date".into(), Value::String(datetime::format_unix_utc(unix)));
      }
    }
    let label = leg_label(index, leg_count);
    let leg = call(provider, kind.operation(), &Value::Object(payload), &label)?;
    let seconds = leg
      .pointer(kind.seconds_pointer())
      .and_then(Value::as_f64)
      .map(|seconds| seconds.round() as i64)
      .ok_or_else(|| error_json("no_route", &format!("MapKit found no route for {label}")))?;
    time = match time {
      LegTime::Departure(unix) => LegTime::Departure(unix + seconds),
      LegTime::Arrival(unix) => LegTime::Arrival(unix - seconds),
    };
    legs[index] = leg;
  }
  Ok(match kind {
    LegKind::Route => agent_shape::route_legs(&legs, arguments),
    LegKind::TravelTime => agent_shape::travel_time_legs(&legs, arguments),
  })
}

/// Opens Apple Maps on this Mac through every stop. A stop with only a MapKit identifier is looked
/// up for its coordinate first.
pub(super) fn open_navigation(arguments: &Value, provider: &dyn ProviderBridge) -> Result<Value, String> {
  let stops = stops(arguments);
  let mut shaped = Vec::with_capacity(stops.len());
  for (index, stop) in stops.iter().enumerate() {
    if stop.get("coordinate").and_then(Value::as_object).is_some() {
      shaped.push(agent_shape::request_endpoint(stop));
      continue;
    }
    let identifier = stop.get("identifier").and_then(Value::as_str).unwrap_or_default();
    let label = stop_label(index, stops.len());
    let place = call(provider, "get_place", &json!({ "identifier": identifier }), &label)?;
    shaped.push(agent_shape::resolved_endpoint(&place, stop));
  }
  let url = agent_shape::navigation_url(&shaped, arguments).ok_or_else(|| {
    error_json(
      "place_without_coordinate",
      "MapKit returned a place without a coordinate; pass that stop's coordinate",
    )
  })?;
  let result = call(provider, "open_navigation", &json!({ "url": url }), "open_navigation")?;
  let opened = result.get("opened").and_then(Value::as_bool) == Some(true);
  Ok(agent_shape::navigation_response(&shaped, &url, opened))
}

/// Source, each waypoint, then destination.
fn stops(arguments: &Value) -> Vec<Value> {
  let mut stops = vec![arguments.get("source").cloned().unwrap_or(Value::Null)];
  if let Some(waypoints) = arguments.get("waypoints").and_then(Value::as_array) {
    stops.extend(waypoints.iter().cloned());
  }
  stops.push(arguments.get("destination").cloned().unwrap_or(Value::Null));
  stops
}

fn text_unix(arguments: &Value, key: &str) -> Option<i64> {
  arguments
    .get(key)
    .and_then(Value::as_str)
    .and_then(datetime::parse_iso_unix)
}

fn call(provider: &dyn ProviderBridge, operation: &str, payload: &Value, label: &str) -> Result<Value, String> {
  let response = provider.call_provider(ProviderRequest {
    provider: "mapkit".into(),
    operation: operation.into(),
    payload_json: payload.to_string(),
  });
  if !response.ok {
    let error = response
      .error_json
      .and_then(|text| serde_json::from_str::<Value>(&text).ok());
    let code = error
      .as_ref()
      .and_then(|error| error.get("code"))
      .and_then(Value::as_str)
      .unwrap_or("provider_error");
    let message = error
      .as_ref()
      .and_then(|error| error.get("message"))
      .and_then(Value::as_str)
      .unwrap_or("provider call failed");
    return Err(error_json(code, &format!("{label}: {message}")));
  }
  serde_json::from_str(&response.payload_json)
    .map_err(|_| error_json("serialization_error", &format!("{label}: MapKit returned invalid JSON")))
}

/// Leg 1 starts at source; the last leg ends at destination.
fn leg_label(index: usize, leg_count: usize) -> String {
  format!(
    "leg {} ({} to {})",
    index + 1,
    stop_label(index, leg_count + 1),
    stop_label(index + 1, leg_count + 1)
  )
}

fn stop_label(index: usize, stop_count: usize) -> String {
  if index == 0 {
    "source".to_string()
  } else if index + 1 == stop_count {
    "destination".to_string()
  } else {
    format!("waypoints[{}]", index - 1)
  }
}

fn error_json(code: &str, message: &str) -> String {
  json!({ "code": code, "message": message }).to_string()
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::config::ProviderResponse;
  use serde_json::json;
  use std::sync::Mutex;

  /// Answers each leg with 30 minutes and 40 km, `get_place` with the Tampa place, and
  /// `open_navigation` with opened. Records each (operation, payload).
  struct Legs {
    calls: Mutex<Vec<(String, Value)>>,
    fail_call: Option<usize>,
  }

  impl Legs {
    fn new(fail_call: Option<usize>) -> Self {
      Self {
        calls: Mutex::new(Vec::new()),
        fail_call,
      }
    }

    fn payloads(&self) -> Vec<Value> {
      self
        .calls
        .lock()
        .expect("calls")
        .iter()
        .map(|(_, payload)| payload.clone())
        .collect()
    }
  }

  impl ProviderBridge for Legs {
    fn call_provider(&self, request: ProviderRequest) -> ProviderResponse {
      let payload: Value = serde_json::from_str(&request.payload_json).expect("payload");
      let mut calls = self.calls.lock().expect("calls");
      let call = calls.len();
      calls.push((request.operation.clone(), payload.clone()));
      if self.fail_call == Some(call) {
        return ProviderResponse {
          ok: false,
          payload_json: String::new(),
          error_json: Some(json!({ "code": "mapkit_error", "message": "Directions not available" }).to_string()),
        };
      }
      // Like Swift: a resolved identifier comes back on the place; `I-FAILED` stands for a lookup
      // that failed, where Swift keeps only the coordinate.
      let place = |endpoint: &Value| {
        let mut place = json!({
          "name": "Unknown Location",
          "location": { "coordinate": endpoint["coordinate"].clone() }
        });
        if let Some(identifier) = endpoint["identifier"].as_str().filter(|id| *id != "I-FAILED") {
          place["identifier"] = json!(identifier);
        }
        place
      };
      let body = match request.operation.as_str() {
        "calculate_route" => json!({
          "source": place(&payload["source"]),
          "destination": place(&payload["destination"]),
          "routes": [
            {
              "name": format!("Road {call}"),
              "distance": 40000,
              "expected_travel_time": 1800,
              "has_highways": call == 1,
              "steps": [{ "instructions": format!("Drive leg {call}"), "distance": 40000 }]
            },
            { "name": "Alternate", "distance": 1, "expected_travel_time": 1 }
          ]
        }),
        "estimate_travel_time" => json!({
          "source": place(&payload["source"]),
          "destination": place(&payload["destination"]),
          "expected_travel_time": 1800,
          "distance": 40000,
          "expected_departure_date": format!("depart-{call}"),
          "expected_arrival_date": format!("arrive-{call}"),
          "transport_type": ["automobile"]
        }),
        "get_place" => json!({
          "name": "Tampa City Hall",
          "identifier": payload["identifier"].clone(),
          "location": { "coordinate": { "latitude": 27.9506, "longitude": -82.4572 } }
        }),
        "open_navigation" => json!({ "opened": true }),
        other => panic!("unexpected operation {other}"),
      };
      ProviderResponse {
        ok: true,
        payload_json: body.to_string(),
        error_json: None,
      }
    }
  }

  fn coordinate(latitude: f64, longitude: f64) -> Value {
    json!({ "coordinate": { "latitude": latitude, "longitude": longitude } })
  }

  fn trip(extra: Value) -> Value {
    let mut arguments = json!({
      "source": coordinate(28.8028, -81.6445),
      "destination": { "identifier": "I-TAMPA", "name": "Tampa", "coordinate": { "latitude": 27.9506, "longitude": -82.4572 } },
      "waypoints": [{ "name": "Wildwood", "coordinate": { "latitude": 28.8653, "longitude": -82.04 } }],
      "requests_alternate_routes": true,
      "highway_preference": "avoid"
    });
    for (key, value) in extra.as_object().expect("object") {
      arguments[key] = value.clone();
    }
    arguments
  }

  const TRIP_URL: &str = "https://maps.apple.com/directions?source=28.8028,-81.6445&waypoint=28.8653,-82.04\
                          &destination=27.9506,-82.4572&destination-place-id=I-TAMPA&mode=driving&avoid=highways";

  #[test]
  fn waypoints_route_each_leg_in_order_and_sum_the_first_routes() {
    let provider = Legs::new(None);
    let shaped = legs(
      LegKind::Route,
      &trip(json!({ "departure_date": "2026-10-20T08:00:00-04:00" })),
      &provider,
    )
    .expect("ok");

    let payloads = provider.payloads();
    assert_eq!(payloads.len(), 2);
    assert_eq!(payloads[0]["destination"]["name"], "Wildwood");
    assert_eq!(payloads[1]["source"]["name"], "Wildwood");
    assert_eq!(payloads[1]["destination"]["identifier"], "I-TAMPA");
    assert_eq!(payloads[0]["departure_date"], "2026-10-20T12:00:00Z");
    assert_eq!(payloads[1]["departure_date"], "2026-10-20T12:30:00Z");
    for payload in &payloads {
      assert!(payload.get("waypoints").is_none());
      assert!(payload.get("requests_alternate_routes").is_none());
      assert_eq!(payload["highway_preference"], "avoid");
    }

    let route = &shaped["routes"][0];
    assert_eq!(shaped["routes"].as_array().expect("routes").len(), 1);
    assert_eq!(route["distance"], 80000.0);
    assert_eq!(route["expected_travel_time"], 3600.0);
    assert_eq!(route["has_highways"], true);
    assert_eq!(route["legs"][0]["name"], "Road 0");
    assert_eq!(route["legs"][1]["steps"][0]["instructions"], "Drive leg 1");
    assert_eq!(shaped["waypoints"][0]["name"], "Wildwood");
    assert_eq!(shaped["destination"]["name"], "Tampa");
    assert_eq!(shaped["maps_url"], TRIP_URL);
  }

  #[test]
  fn arrival_date_routes_backward_from_the_last_leg() {
    let provider = Legs::new(None);
    legs(
      LegKind::Route,
      &trip(json!({ "arrival_date": "2026-10-20T10:00:00Z" })),
      &provider,
    )
    .expect("ok");
    let payloads = provider.payloads();
    assert_eq!(payloads[0]["source"]["name"], "Wildwood");
    assert_eq!(payloads[0]["arrival_date"], "2026-10-20T10:00:00Z");
    assert_eq!(payloads[1]["destination"]["name"], "Wildwood");
    assert_eq!(payloads[1]["arrival_date"], "2026-10-20T09:30:00Z");
  }

  #[test]
  fn a_failed_leg_names_the_leg_and_keeps_the_code() {
    let provider = Legs::new(Some(1));
    let error = legs(LegKind::Route, &trip(json!({})), &provider).expect_err("leg 2 fails");
    let error: Value = serde_json::from_str(&error).expect("json");
    assert_eq!(error["code"], "mapkit_error");
    assert_eq!(
      error["message"],
      "leg 2 (waypoints[0] to destination): Directions not available"
    );
  }

  #[test]
  fn a_stop_whose_identifier_lookup_failed_links_by_coordinate() {
    let provider = Legs::new(None);
    let mut arguments = trip(json!({}));
    arguments["destination"]["identifier"] = json!("I-FAILED");
    let shaped = legs(LegKind::Route, &arguments, &provider).expect("ok");
    assert!(shaped["destination"].get("identifier").is_none());
    let url = shaped["maps_url"].as_str().expect("maps_url");
    assert!(url.contains("destination=27.9506,-82.4572&mode=driving"), "{url}");
    assert!(!url.contains("place-id"), "{url}");
  }

  #[test]
  fn travel_time_legs_sum_and_take_the_first_departure_and_last_arrival() {
    let provider = Legs::new(None);
    let shaped = legs(
      LegKind::TravelTime,
      &trip(json!({ "departure_date": "2026-10-20T12:00:00Z" })),
      &provider,
    )
    .expect("ok");
    let payloads = provider.payloads();
    assert_eq!(payloads[1]["departure_date"], "2026-10-20T12:30:00Z");
    assert_eq!(shaped["expected_travel_time"], 3600.0);
    assert_eq!(shaped["distance"], 80000.0);
    assert_eq!(shaped["expected_departure_date"], "depart-0");
    assert_eq!(shaped["expected_arrival_date"], "arrive-1");
    assert_eq!(shaped["legs"].as_array().expect("legs").len(), 2);
    assert_eq!(shaped["legs"][1]["expected_departure_date"], "depart-1");
    assert_eq!(shaped["waypoints"][0]["name"], "Wildwood");
    assert_eq!(shaped["maps_url"], TRIP_URL);
  }

  #[test]
  fn open_navigation_looks_up_identifier_stops_and_opens_the_trip_url() {
    let provider = Legs::new(None);
    let mut arguments = trip(json!({}));
    arguments["destination"] = json!({ "identifier": "I-TAMPA", "name": "Tampa" });
    let shaped = open_navigation(&arguments, &provider).expect("ok");

    let calls = provider.calls.lock().expect("calls").clone();
    assert_eq!(calls.len(), 2, "{calls:?}");
    assert_eq!(calls[0].0, "get_place");
    assert_eq!(calls[0].1, json!({ "identifier": "I-TAMPA" }));
    assert_eq!(calls[1].0, "open_navigation");
    assert_eq!(calls[1].1, json!({ "url": TRIP_URL }));
    assert_eq!(shaped["opened"], true);
    assert_eq!(shaped["maps_url"], TRIP_URL);
    assert_eq!(shaped["destination"]["name"], "Tampa");
    assert_eq!(
      shaped["destination"]["maps_url"],
      "https://maps.apple.com/place?place-id=I-TAMPA"
    );
    assert_eq!(
      shaped["waypoints"][0]["maps_url"],
      "https://maps.apple.com/place?coordinate=28.8653,-82.04&name=Wildwood"
    );
  }

  #[test]
  fn legs_without_a_date_leave_now_and_chain_each_leg() {
    for kind in [LegKind::Route, LegKind::TravelTime] {
      let provider = Legs::new(None);
      let before = jiff::Timestamp::now().as_second();
      legs(kind, &trip(json!({})), &provider).expect("ok");
      let payloads = provider.payloads();
      let departure = |index: usize| {
        datetime::parse_iso_unix(payloads[index]["departure_date"].as_str().expect("departure_date")).expect("instant")
      };
      assert!(departure(0) >= before, "first leg leaves now");
      assert_eq!(
        departure(1) - departure(0),
        1800,
        "second leg leaves when the first arrives"
      );
    }
  }

  #[test]
  fn waypoint_place_ids_are_positional_with_an_empty_id_for_a_stop_without_one() {
    let provider = Legs::new(None);
    let mut arguments = trip(json!({}));
    arguments["waypoints"] = json!([
      { "name": "Wildwood", "coordinate": { "latitude": 28.8653, "longitude": -82.04 } },
      { "identifier": "I-PUBLIX", "coordinate": { "latitude": 28.8262, "longitude": -81.6424 } }
    ]);
    let shaped = open_navigation(&arguments, &provider).expect("ok");
    assert_eq!(
      shaped["maps_url"],
      "https://maps.apple.com/directions?source=28.8028,-81.6445\
       &waypoint=28.8653,-82.04&waypoint-place-id=&waypoint=28.8262,-81.6424&waypoint-place-id=I-PUBLIX\
       &destination=27.9506,-82.4572&destination-place-id=I-TAMPA&mode=driving&avoid=highways"
    );
  }

  #[test]
  fn open_navigation_stops_before_opening_when_a_lookup_fails() {
    let provider = Legs::new(Some(0));
    let mut arguments = trip(json!({}));
    arguments["source"] = json!({ "identifier": "I-GONE" });
    let error = open_navigation(&arguments, &provider).expect_err("lookup fails");
    let error: Value = serde_json::from_str(&error).expect("json");
    assert_eq!(error["message"], "source: Directions not available");
    assert_eq!(provider.calls.lock().expect("calls").len(), 1);
  }
}

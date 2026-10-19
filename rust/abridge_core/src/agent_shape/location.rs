//! A GPS fix without the invalid sensor sentinels Core Location uses for "no reading".

use serde_json::{Map, Value};

use super::util::{copy_number, copy_text};

pub(crate) fn current_location(value: &Value) -> Value {
  let location = value.get("location").unwrap_or(value);
  let mut object = Map::new();
  if let Some(coordinate) = location.get("coordinate") {
    let mut coordinate_object = Map::new();
    copy_number(&mut coordinate_object, coordinate, "latitude");
    copy_number(&mut coordinate_object, coordinate, "longitude");
    if !coordinate_object.is_empty() {
      object.insert("coordinate".into(), Value::Object(coordinate_object));
    }
  }
  copy_text(&mut object, location, "timestamp");
  copy_number(&mut object, location, "altitude");
  copy_non_negative(&mut object, location, "horizontal_accuracy");
  copy_non_negative(&mut object, location, "vertical_accuracy");
  copy_non_negative(&mut object, location, "course");
  copy_non_negative(&mut object, location, "speed");
  if let Some(floor) = location.get("floor").and_then(super::util::slim) {
    object.insert("floor".into(), floor);
  }
  Value::Object(Map::from_iter([("location".to_string(), Value::Object(object))]))
}

fn copy_non_negative(object: &mut Map<String, Value>, source: &Value, key: &str) {
  if source
    .get(key)
    .and_then(Value::as_f64)
    .is_some_and(|number| number >= 0.0)
  {
    copy_number(object, source, key);
  }
}

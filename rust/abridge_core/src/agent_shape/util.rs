//! Shared JSON slimming. Absent keys mean null, false, or empty.

use serde_json::{Map, Value};

pub(crate) fn text<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
  value.get(key).and_then(Value::as_str).filter(|text| !text.is_empty())
}

pub(crate) fn put_text(object: &mut Map<String, Value>, key: &str, value: Option<&str>) {
  if let Some(text) = value.filter(|text| !text.is_empty()) {
    object.insert(key.to_string(), Value::String(text.to_string()));
  }
}

pub(crate) fn copy_text(object: &mut Map<String, Value>, source: &Value, key: &str) {
  put_text(object, key, text(source, key));
}

pub(crate) fn copy_true(object: &mut Map<String, Value>, source: &Value, key: &str) {
  if source.get(key).and_then(Value::as_bool) == Some(true) {
    object.insert(key.to_string(), Value::Bool(true));
  }
}

pub(crate) fn copy_number(object: &mut Map<String, Value>, source: &Value, key: &str) {
  if let Some(number) = source.get(key).filter(|value| value.is_number()) {
    object.insert(key.to_string(), number.clone());
  }
}

pub(crate) fn snippet(text: &str) -> String {
  let flat = text.split_whitespace().collect::<Vec<_>>().join(" ");
  let mut chars = flat.chars();
  let head: String = chars.by_ref().take(140).collect();
  if chars.next().is_some() {
    format!("{head}…")
  } else {
    head
  }
}

/// Drops null, false, empty strings, and empty containers. Numbers, including 0, stay.
pub(crate) fn slim(value: &Value) -> Option<Value> {
  slim_dropping(value, &[])
}

pub(crate) fn slim_dropping(value: &Value, drop_keys: &[&str]) -> Option<Value> {
  match value {
    Value::Null => None,
    Value::Bool(false) => None,
    Value::Bool(true) => Some(Value::Bool(true)),
    Value::Number(number) => Some(Value::Number(number.clone())),
    Value::String(text) if text.is_empty() => None,
    Value::String(text) => Some(Value::String(text.clone())),
    Value::Array(items) => {
      let items: Vec<Value> = items.iter().filter_map(|item| slim_dropping(item, drop_keys)).collect();
      if items.is_empty() {
        None
      } else {
        Some(Value::Array(items))
      }
    }
    Value::Object(map) => {
      let mut object = Map::new();
      for (key, item) in map {
        if drop_keys.contains(&key.as_str()) {
          continue;
        }
        if let Some(item) = slim_dropping(item, drop_keys) {
          object.insert(key.clone(), item);
        }
      }
      if object.is_empty() {
        None
      } else {
        Some(Value::Object(object))
      }
    }
  }
}

pub(crate) fn date_parts(value: &Value) -> Option<Value> {
  let source = value.as_object()?;
  let mut object = Map::new();
  for key in [
    "year",
    "month",
    "day",
    "hour",
    "minute",
    "second",
    "weekday",
    "time_zone",
  ] {
    let Some(part) = source.get(key) else {
      continue;
    };
    if part.is_number() || part.as_str().is_some_and(|text| !text.is_empty()) {
      object.insert(key.to_string(), part.clone());
    }
  }
  if object.is_empty() {
    None
  } else {
    Some(Value::Object(object))
  }
}

pub(crate) fn matches_json(matches: &[crate::fuzzy::Match]) -> Value {
  Value::Array(
    matches
      .iter()
      .map(|hit| {
        serde_json::json!({
          "field": hit.field,
          "excerpt": hit.excerpt,
        })
      })
      .collect(),
  )
}

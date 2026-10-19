//! Contact shapes. Photos leave the JSON: list and search never carry bytes; get and writes
//! attach the photo as MCP image content.

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde_json::{Map, Value, json};

use crate::rendition::{self, MODEL_IMAGE_MAX_BASE64, MODEL_IMAGE_TYPES};

use super::util::{self, copy_text, copy_true, put_text, text};

pub(crate) fn summary(value: &Value) -> Value {
  let mut object = Map::new();
  copy_text(&mut object, value, "identifier");
  copy_text(&mut object, value, "container_identifier");
  put_text(&mut object, "name", display_name(value).as_deref());
  copy_text(&mut object, value, "nickname");
  copy_text(&mut object, value, "organization_name");
  copy_text(&mut object, value, "job_title");
  if let Some(phone) = first_labeled_string(value.get("phone_numbers"), "string_value") {
    object.insert("phone".into(), Value::String(phone));
  }
  if let Some(email) = first_labeled_string(value.get("email_addresses"), "") {
    object.insert("email".into(), Value::String(email));
  }
  copy_true(&mut object, value, "image_data_available");
  Value::Object(object)
}

pub(crate) fn detail(value: &Value) -> (Value, Vec<Value>) {
  let mut object = Map::new();
  copy_text(&mut object, value, "identifier");
  copy_text(&mut object, value, "container_identifier");
  copy_text(&mut object, value, "contact_type");
  put_text(&mut object, "name", display_name(value).as_deref());
  for key in [
    "name_prefix",
    "given_name",
    "middle_name",
    "family_name",
    "name_suffix",
    "nickname",
    "organization_name",
    "department_name",
    "job_title",
    "phonetic_given_name",
    "phonetic_middle_name",
    "phonetic_family_name",
    "phonetic_organization_name",
    "previous_family_name",
    "note",
  ] {
    copy_text(&mut object, value, key);
  }
  copy_true(&mut object, value, "image_data_available");
  if let Some(birthday) = value.get("birthday").and_then(util::date_parts) {
    object.insert("birthday".into(), birthday);
  }
  if let Some(birthday) = value.get("non_gregorian_birthday").and_then(util::date_parts) {
    object.insert("non_gregorian_birthday".into(), birthday);
  }
  for key in [
    "phone_numbers",
    "email_addresses",
    "postal_addresses",
    "url_addresses",
    "contact_relations",
    "social_profiles",
    "instant_message_addresses",
    "dates",
  ] {
    if let Some(items) = labeled_values(value.get(key)) {
      object.insert(key.to_string(), items);
    }
  }

  let identifier = text(value, "identifier").unwrap_or("contact");
  let mut images = Vec::new();
  if let Some(encoded) = text(value, "image_data") {
    push_image(&mut images, encoded, &format!("contact://{identifier}/image"));
  } else if let Some(encoded) = text(value, "thumbnail_image_data") {
    push_image(&mut images, encoded, &format!("contact://{identifier}/thumbnail"));
  }

  (Value::Object(object), images)
}

pub(crate) fn group(value: &Value) -> Value {
  util::slim(value).unwrap_or_else(|| json!({}))
}

pub(crate) fn container(value: &Value) -> Value {
  let mut object = Map::new();
  copy_text(&mut object, value, "identifier");
  copy_text(&mut object, value, "name");
  copy_text(&mut object, value, "type");
  copy_true(&mut object, value, "is_default");
  Value::Object(object)
}

pub(crate) fn fields(value: &Value) -> Vec<super::rank::OwnedField> {
  let mut fields = Vec::new();
  if let Some(name) = display_name(value) {
    fields.push(owned("name", name, 8, false));
  }
  push_text(&mut fields, value, "nickname", 6, false);
  push_text(&mut fields, value, "organization_name", 4, false);
  push_text(&mut fields, value, "job_title", 4, false);
  if let Some(emails) = joined_labeled(value.get("email_addresses")) {
    fields.push(owned("email", emails, 4, false));
  }
  if let Some(phones) = joined_labeled(value.get("phone_numbers")) {
    fields.push(owned("phone", phones, 4, false));
  }
  push_text(&mut fields, value, "note", 2, true);
  fields
}

fn push_text(fields: &mut Vec<super::rank::OwnedField>, value: &Value, key: &'static str, weight: u32, per_line: bool) {
  if let Some(text) = text(value, key) {
    fields.push(owned(key, text.to_string(), weight, per_line));
  }
}

fn owned(label: &str, text: String, weight: u32, per_line: bool) -> super::rank::OwnedField {
  super::rank::OwnedField {
    label: label.to_string(),
    text,
    weight,
    per_line,
  }
}

fn display_name(value: &Value) -> Option<String> {
  let parts: Vec<&str> = ["name_prefix", "given_name", "middle_name", "family_name", "name_suffix"]
    .into_iter()
    .filter_map(|key| text(value, key))
    .collect();
  if parts.is_empty() {
    text(value, "organization_name")
      .or_else(|| text(value, "nickname"))
      .map(str::to_string)
  } else {
    Some(parts.join(" "))
  }
}

fn first_labeled_string(value: Option<&Value>, nested: &str) -> Option<String> {
  let entry = value?.as_array()?.first()?;
  labeled_string(entry, nested)
}

fn joined_labeled(value: Option<&Value>) -> Option<String> {
  let items = value?.as_array()?;
  let joined = items
    .iter()
    .filter_map(|entry| labeled_string(entry, "string_value").or_else(|| labeled_string(entry, "")))
    .collect::<Vec<_>>()
    .join("\n");
  if joined.is_empty() { None } else { Some(joined) }
}

fn labeled_string(entry: &Value, nested: &str) -> Option<String> {
  match entry.get("value")? {
    Value::String(text) if !text.is_empty() => Some(text.clone()),
    Value::Object(object) if !nested.is_empty() => object
      .get(nested)
      .and_then(Value::as_str)
      .filter(|text| !text.is_empty())
      .map(str::to_string),
    Value::Object(object) => object
      .values()
      .find_map(|item| item.as_str().filter(|text| !text.is_empty()).map(str::to_string)),
    _ => None,
  }
}

fn labeled_values(value: Option<&Value>) -> Option<Value> {
  let items = value?.as_array()?;
  let mapped: Vec<Value> = items.iter().filter_map(labeled_value).collect();
  if mapped.is_empty() {
    None
  } else {
    Some(Value::Array(mapped))
  }
}
fn labeled_value(entry: &Value) -> Option<Value> {
  let mut object = Map::new();
  if let Some(label) = text(entry, "label") {
    object.insert("label".into(), Value::String(contact_label(label)));
  }
  copy_text(&mut object, entry, "identifier");
  match entry.get("value")? {
    Value::String(text) if !text.is_empty() => {
      object.insert("value".into(), Value::String(text.clone()));
    }
    Value::Object(map) => {
      if let Some(phone) = map
        .get("string_value")
        .and_then(Value::as_str)
        .filter(|text| !text.is_empty())
      {
        object.insert("value".into(), Value::String(phone.to_string()));
      } else if let Some(slimmed) = util::slim(&Value::Object(map.clone())) {
        object.insert("value".into(), slimmed);
      }
    }
    other => {
      if let Some(slimmed) = util::slim(other) {
        object.insert("value".into(), slimmed);
      }
    }
  }
  if object.is_empty() {
    None
  } else {
    Some(Value::Object(object))
  }
}

fn push_image(images: &mut Vec<Value>, encoded: &str, uri: &str) {
  let Ok(bytes) = STANDARD.decode(encoded.trim()) else {
    return;
  };
  let mime = sniff(&bytes).unwrap_or("application/octet-stream");
  if MODEL_IMAGE_TYPES.contains(&mime) && encoded.len() <= MODEL_IMAGE_MAX_BASE64 {
    images.push(json!({ "type": "image", "data": encoded, "mimeType": mime }));
  } else if let Some(jpeg) = rendition::jpeg_rendition_of_bytes(&bytes) {
    images.push(json!({ "type": "image", "data": STANDARD.encode(jpeg), "mimeType": "image/jpeg" }));
  } else if bytes.len() as u64 <= rendition::MAX_RESOURCE_BYTES {
    images.push(json!({
      "type": "resource",
      "resource": { "uri": uri, "mimeType": mime, "blob": encoded }
    }));
  }
}

fn sniff(bytes: &[u8]) -> Option<&'static str> {
  if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
    Some("image/jpeg")
  } else if bytes.starts_with(&[0x89, b'P', b'N', b'G']) {
    Some("image/png")
  } else if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
    Some("image/gif")
  } else if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
    Some("image/webp")
  } else {
    None
  }
}

fn contact_label(label: &str) -> String {
  if let Some(token) = label.strip_prefix("_$!<").and_then(|rest| rest.strip_suffix(">!$_")) {
    return humanize_token(token);
  }
  match label {
    "iPhone" => "iphone".to_string(),
    "Apple Watch" => "apple watch".to_string(),
    "iCloud" => "icloud".to_string(),
    other => other.to_string(),
  }
}

fn humanize_token(token: &str) -> String {
  if token.chars().any(char::is_whitespace) {
    return token
      .split_whitespace()
      .collect::<Vec<_>>()
      .join(" ")
      .to_ascii_lowercase();
  }
  let chars: Vec<char> = token.chars().collect();
  let mut words = Vec::new();
  let mut word = String::new();
  for (index, ch) in chars.iter().copied().enumerate() {
    let prev_lower = index > 0 && chars[index - 1].is_lowercase();
    let next_lower = chars.get(index + 1).is_some_and(|next| next.is_lowercase());
    if ch.is_uppercase() && !word.is_empty() && (prev_lower || next_lower) {
      words.push(std::mem::take(&mut word));
    }
    word.push(ch);
  }
  if !word.is_empty() {
    words.push(word);
  }
  let mut words: Vec<String> = words.into_iter().map(|word| word.to_ascii_lowercase()).collect();
  if words.first().is_some_and(|word| word == "i") && words.len() > 1 {
    let rest = words.remove(1);
    words[0].push_str(&rest);
  }
  words.join(" ")
}

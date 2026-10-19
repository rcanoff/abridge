//! Event and reminder shapes. List rows are enough to pick an item; get and writes return the detail.

use serde_json::{Map, Value, json};

use super::util::{self, copy_number, copy_text, copy_true, put_text, text};

pub(crate) fn calendar_summary(value: &Value) -> Value {
  let mut object = Map::new();
  copy_text(&mut object, value, "calendar_identifier");
  copy_text(&mut object, value, "title");
  copy_text(&mut object, value, "type");
  if let Some(source) = value.get("source").and_then(source_ref) {
    object.insert("source".into(), source);
  }
  if let Some(color) = value.get("cg_color").and_then(color_hex) {
    object.insert("color".into(), Value::String(color));
  }
  copy_true(&mut object, value, "allows_content_modifications");
  copy_true(&mut object, value, "is_subscribed");
  copy_true(&mut object, value, "is_immutable");
  Value::Object(object)
}

pub(crate) fn event_summary(value: &Value) -> Value {
  let mut object = Map::new();
  copy_text(&mut object, value, "event_identifier");
  copy_text(&mut object, value, "title");
  put_event_times(&mut object, value, false);
  copy_text(&mut object, value, "time_zone");
  copy_text(&mut object, value, "location");
  copy_true(&mut object, value, "is_all_day");
  copy_event_fact(&mut object, value, "status");
  if flag_or_items(value, "has_alarms", "alarms") {
    object.insert("has_alarms".into(), Value::Bool(true));
  }
  if flag_or_items(value, "has_recurrence_rules", "recurrence_rules") {
    object.insert("has_recurrence_rules".into(), Value::Bool(true));
  }
  if let Some(notes) = event_notes(value) {
    put_text(&mut object, "snippet", Some(&util::snippet(&notes)));
  }
  if let Some(calendar) = value.get("calendar") {
    object.insert("calendar".into(), calendar_ref(calendar));
  }
  Value::Object(object)
}

pub(crate) fn event_detail(value: &Value) -> Value {
  let mut object = Map::new();
  for key in [
    "event_identifier",
    "title",
    "location",
    "url",
    "time_zone",
    "creation_date",
    "last_modified_date",
    "birthday_contact_identifier",
  ] {
    copy_text(&mut object, value, key);
  }
  copy_event_fact(&mut object, value, "availability");
  copy_event_fact(&mut object, value, "status");
  if let Some(notes) = event_notes(value) {
    object.insert("notes".into(), Value::String(notes));
  }
  put_event_times(&mut object, value, true);
  copy_true(&mut object, value, "is_all_day");
  copy_true(&mut object, value, "is_detached");
  if let Some(calendar) = value.get("calendar") {
    object.insert("calendar".into(), calendar_summary(calendar));
  }
  if let Some(organizer) = value.get("organizer").and_then(person) {
    object.insert("organizer".into(), organizer);
  }
  if let Some(attendees) = people(value.get("attendees")) {
    object.insert("attendees".into(), attendees);
  }
  if let Some(location) = value.get("structured_location").and_then(structured_location) {
    object.insert("structured_location".into(), location);
  }
  if let Some(alarms) = mapped_array(value.get("alarms"), alarm) {
    object.insert("alarms".into(), alarms);
  }
  if let Some(rules) = mapped_array(value.get("recurrence_rules"), recurrence) {
    object.insert("recurrence_rules".into(), rules);
  }
  Value::Object(object)
}

pub(crate) fn reminder_summary(value: &Value) -> Value {
  let mut object = Map::new();
  copy_text(&mut object, value, "calendar_item_identifier");
  copy_text(&mut object, value, "title");
  copy_text(&mut object, value, "time_zone");
  copy_text(&mut object, value, "location");
  copy_true(&mut object, value, "is_completed");
  copy_text(&mut object, value, "completion_date");
  if let Some(priority) = value.get("priority").and_then(Value::as_i64)
    && priority != 0
  {
    object.insert("priority".into(), json!(priority));
  }
  if put_reminder_date(&mut object, value, "due_date_components", "due_date") {
    object.insert("floating".into(), Value::Bool(true));
  }
  if flag_or_items(value, "has_alarms", "alarms") {
    object.insert("has_alarms".into(), Value::Bool(true));
  }
  if flag_or_items(value, "has_recurrence_rules", "recurrence_rules") {
    object.insert("has_recurrence_rules".into(), Value::Bool(true));
  }
  if let Some(notes) = text(value, "notes") {
    put_text(&mut object, "snippet", Some(&util::snippet(notes)));
  }
  if let Some(calendar) = value.get("calendar") {
    object.insert("calendar".into(), calendar_ref(calendar));
  }
  Value::Object(object)
}

pub(crate) fn reminder_detail(value: &Value) -> Value {
  let mut object = Map::new();
  for key in [
    "calendar_item_identifier",
    "title",
    "location",
    "url",
    "notes",
    "time_zone",
    "creation_date",
    "last_modified_date",
    "completion_date",
  ] {
    copy_text(&mut object, value, key);
  }
  copy_true(&mut object, value, "is_completed");
  if let Some(priority) = value.get("priority").and_then(Value::as_i64)
    && priority != 0
  {
    object.insert("priority".into(), json!(priority));
  }
  let due_floating = put_reminder_date(&mut object, value, "due_date_components", "due_date");
  let start_floating = put_reminder_date(&mut object, value, "start_date_components", "start_date");
  if due_floating || start_floating {
    object.insert("floating".into(), Value::Bool(true));
  }
  if let Some(calendar) = value.get("calendar") {
    object.insert("calendar".into(), calendar_summary(calendar));
  }
  if let Some(alarms) = mapped_array(value.get("alarms"), alarm) {
    object.insert("alarms".into(), alarms);
  }
  if let Some(rules) = mapped_array(value.get("recurrence_rules"), recurrence) {
    object.insert("recurrence_rules".into(), rules);
  }
  Value::Object(object)
}

pub(crate) fn event_fields(value: &Value) -> Vec<super::rank::OwnedField> {
  let mut fields = text_fields(value, &[("title", 8, false), ("location", 4, false)]);
  if let Some(notes) = event_notes(value) {
    fields.push(super::rank::OwnedField {
      label: "notes".into(),
      text: notes,
      weight: 2,
      per_line: true,
    });
  }
  fields
}

pub(crate) fn reminder_fields(value: &Value) -> Vec<super::rank::OwnedField> {
  text_fields(
    value,
    &[("title", 8, false), ("location", 4, false), ("notes", 2, true)],
  )
}

fn text_fields(value: &Value, specs: &[(&str, u32, bool)]) -> Vec<super::rank::OwnedField> {
  specs
    .iter()
    .filter_map(|(label, weight, per_line)| {
      text(value, label).map(|text| super::rank::OwnedField {
        label: (*label).to_string(),
        text: text.to_string(),
        weight: *weight,
        per_line: *per_line,
      })
    })
    .collect()
}

fn calendar_ref(value: &Value) -> Value {
  let mut object = Map::new();
  copy_text(&mut object, value, "calendar_identifier");
  copy_text(&mut object, value, "title");
  Value::Object(object)
}

fn flag_or_items(value: &Value, flag: &str, items: &str) -> bool {
  value.get(flag).and_then(Value::as_bool) == Some(true)
    || value
      .get(items)
      .and_then(Value::as_array)
      .is_some_and(|items| !items.is_empty())
}

fn people(value: Option<&Value>) -> Option<Value> {
  let items = value?.as_array()?;
  let people: Vec<Value> = items.iter().filter_map(person).collect();
  if people.is_empty() {
    None
  } else {
    Some(Value::Array(people))
  }
}

fn person(value: &Value) -> Option<Value> {
  let mut object = Map::new();
  copy_text(&mut object, value, "name");
  copy_text(&mut object, value, "participant_status");
  copy_text(&mut object, value, "participant_role");
  copy_text(&mut object, value, "participant_type");
  copy_true(&mut object, value, "is_current_user");
  copy_text(&mut object, value, "url");
  if object.is_empty() {
    None
  } else {
    Some(Value::Object(object))
  }
}

fn structured_location(value: &Value) -> Option<Value> {
  if value.is_null() {
    return None;
  }
  let mut object = Map::new();
  copy_text(&mut object, value, "title");
  if let Some(radius) = value.get("radius").and_then(Value::as_f64)
    && radius > 0.0
  {
    copy_number(&mut object, value, "radius");
  }
  if let Some(geo) = value.get("geo_location").filter(|geo| !geo.is_null()) {
    let mut coordinate = Map::new();
    copy_number(&mut coordinate, geo, "latitude");
    copy_number(&mut coordinate, geo, "longitude");
    if !coordinate.is_empty() {
      object.insert("geo_location".into(), Value::Object(coordinate));
    }
  }
  if object.is_empty() {
    None
  } else {
    Some(Value::Object(object))
  }
}

fn alarm(value: &Value) -> Option<Value> {
  let mut object = Map::new();
  copy_text(&mut object, value, "absolute_date");
  copy_number(&mut object, value, "relative_offset");
  if let Some(proximity) = text(value, "proximity")
    && proximity != "none"
  {
    object.insert("proximity".into(), Value::String(proximity.to_string()));
  }
  copy_text(&mut object, value, "email_address");
  copy_text(&mut object, value, "type");
  if let Some(location) = value.get("structured_location").and_then(structured_location) {
    object.insert("structured_location".into(), location);
  }
  if object.is_empty() {
    None
  } else {
    Some(Value::Object(object))
  }
}

fn recurrence(value: &Value) -> Option<Value> {
  let mut object = Map::new();
  copy_text(&mut object, value, "frequency");
  copy_number(&mut object, value, "interval");
  copy_number(&mut object, value, "first_day_of_the_week");
  for key in [
    "days_of_the_week",
    "days_of_the_month",
    "days_of_the_year",
    "months_of_the_year",
    "weeks_of_the_year",
    "set_positions",
  ] {
    if let Some(items) = value.get(key).and_then(util::slim) {
      object.insert(key.to_string(), items);
    }
  }
  if let Some(end) = value.get("recurrence_end").and_then(util::slim) {
    object.insert("recurrence_end".into(), end);
  }
  if object.is_empty() {
    None
  } else {
    Some(Value::Object(object))
  }
}

fn mapped_array(value: Option<&Value>, map: impl Fn(&Value) -> Option<Value>) -> Option<Value> {
  let items = value?.as_array()?;
  let mapped: Vec<Value> = items.iter().filter_map(map).collect();
  if mapped.is_empty() {
    None
  } else {
    Some(Value::Array(mapped))
  }
}

fn color_hex(value: &Value) -> Option<String> {
  let components = value.get("components")?.as_array()?;
  let numbers: Vec<f64> = components.iter().filter_map(Value::as_f64).take(3).collect();
  if numbers.len() < 3 {
    return None;
  }
  let scale = if numbers.iter().any(|number| *number > 1.0) {
    1.0
  } else {
    255.0
  };
  let channel = |number: f64| (number * scale).round().clamp(0.0, 255.0) as u8;
  Some(format!(
    "#{:02X}{:02X}{:02X}",
    channel(numbers[0]),
    channel(numbers[1]),
    channel(numbers[2])
  ))
}

fn source_ref(source: &Value) -> Option<Value> {
  let mut object = Map::new();
  copy_text(&mut object, source, "source_identifier");
  copy_text(&mut object, source, "title");
  if let Some(kind) = text(source, "source_type").or_else(|| text(source, "type")) {
    object.insert("type".into(), Value::String(kind.to_string()));
  }
  if object.is_empty() {
    None
  } else {
    Some(Value::Object(object))
  }
}

fn event_notes(value: &Value) -> Option<String> {
  text(value, "notes")
    .map(notes_markdown)
    .filter(|notes| !notes.is_empty())
}

/// True when the value written is a floating wall time (no offset).
fn put_reminder_date(object: &mut Map<String, Value>, value: &Value, from: &str, to: &str) -> bool {
  let Some(components) = value.get(from) else {
    return false;
  };
  match reminder_date(components) {
    Some((date, floating)) => {
      object.insert(to.to_string(), Value::String(date));
      floating
    }
    None => false,
  }
}

/// `YYYY-MM-DD` when there is no time. A components `time_zone` stamps a time with `Z` / `±HH:MM`.
/// A time with no components zone is floating: that wall time with no offset. The reminder's
/// `time_zone` and the server zone do not stamp it.
fn reminder_date(value: &Value) -> Option<(String, bool)> {
  let year = component(value, "year").filter(|year| (1..=9999).contains(year))?;
  let month = component(value, "month")?;
  let day = component(value, "day")?;
  let date = crate::datetime::calendar_date(year, month, day)?;
  let has_time = value.get("hour").is_some_and(|part| !part.is_null())
    || value.get("minute").is_some_and(|part| !part.is_null())
    || value.get("second").is_some_and(|part| !part.is_null());
  if !has_time {
    return Some((date, false));
  }
  let hour = component(value, "hour").unwrap_or(0);
  let minute = component(value, "minute").unwrap_or(0);
  if !(0..=23).contains(&hour) || !(0..=59).contains(&minute) {
    return None;
  }
  let second = match component(value, "second") {
    Some(second) if (0..=59).contains(&second) => Some(second),
    Some(_) => return None,
    None => None,
  };
  let mut formatted = match second {
    Some(second) => format!("{date}T{hour:02}:{minute:02}:{second:02}"),
    None => format!("{date}T{hour:02}:{minute:02}"),
  };
  if let Some(zone) = text(value, "time_zone") {
    if let Some(offset) = crate::datetime::zone_offset_suffix(zone, year, month, day, hour, minute, second.unwrap_or(0))
    {
      formatted.push_str(&offset);
    }
    return Some((formatted, false));
  }
  if second.is_none() {
    formatted.push_str(":00");
  }
  Some((formatted, true))
}

fn copy_event_fact(object: &mut Map<String, Value>, value: &Value, key: &str) {
  let Some(fact) = text(value, key) else {
    return;
  };
  let sentinel = matches!((key, fact), ("status", "none") | ("availability", "not_supported"));
  if !sentinel {
    object.insert(key.to_string(), Value::String(fact.to_string()));
  }
}

fn put_event_times(object: &mut Map<String, Value>, value: &Value, include_occurrence: bool) {
  let all_day = value.get("is_all_day").and_then(Value::as_bool) == Some(true);
  let zone = text(value, "time_zone");
  put_event_time(object, value, "start_date", zone, all_day);
  put_event_time(object, value, "end_date", zone, all_day);
  if include_occurrence {
    put_event_time(object, value, "occurrence_date", zone, all_day);
  }
}

fn put_event_time(object: &mut Map<String, Value>, value: &Value, key: &str, zone: Option<&str>, all_day: bool) {
  let Some(raw) = text(value, key) else {
    return;
  };
  let formatted = if all_day && key == "end_date" {
    crate::datetime::format_all_day_end(raw, zone)
  } else {
    crate::datetime::format_event_time(raw, zone, all_day)
  }
  .unwrap_or_else(|| raw.to_string());
  object.insert(key.to_string(), Value::String(formatted));
}

pub(crate) fn event_search_bounds(now_unix: i64) -> (i64, i64) {
  const DAY: i64 = 86_400;
  (
    now_unix.saturating_sub(365 * DAY),
    now_unix.saturating_add(2 * 365 * DAY),
  )
}

pub(crate) fn format_unix_utc(unix: i64) -> String {
  crate::datetime::format_unix_utc(unix)
}

pub(crate) fn parse_iso_unix(text: &str) -> Option<i64> {
  crate::datetime::parse_iso_unix(text)
}

fn component(value: &Value, key: &str) -> Option<i64> {
  let part = value.get(key)?;
  if part.is_null() { None } else { part.as_i64() }
}

fn notes_markdown(raw: &str) -> String {
  let normalized = raw.replace("\r\n", "\n").replace('\r', "\n");
  collapse_blank_lines(&notes_markup(&normalized))
}

fn notes_markup(raw: &str) -> String {
  let bytes = raw.as_bytes();
  let mut out = String::new();
  let mut index = 0;
  while index < bytes.len() {
    if bytes[index] != b'<' {
      let start = index;
      while index < bytes.len() && bytes[index] != b'<' {
        index += 1;
      }
      out.push_str(&decode_entities(&raw[start..index]));
      continue;
    }
    let Some(end) = tag_end(bytes, index) else {
      out.push_str(&decode_entities(&raw[index..]));
      break;
    };
    let tag = &raw[index..=end];
    let name = tag_name(tag);
    if name.eq_ignore_ascii_case("br") {
      out.push('\n');
      index = end + 1;
      continue;
    }
    if name.eq_ignore_ascii_case("a")
      && let Some(href) = attr_value(tag, "href")
    {
      let close = close_tag(bytes, end + 1, "a");
      let inner_end = close.unwrap_or(end + 1);
      let label = notes_markup(&raw[end + 1..inner_end]).trim().to_string();
      let href = decode_entities(&href);
      if label.is_empty() {
        out.push_str(&href);
      } else {
        out.push('[');
        out.push_str(&label);
        out.push_str("](");
        out.push_str(&href);
        out.push(')');
      }
      index = close
        .and_then(|at| tag_end(bytes, at).map(|tag_end| tag_end + 1))
        .unwrap_or(end + 1);
      continue;
    }
    index = end + 1;
  }
  out
}

fn tag_end(bytes: &[u8], start: usize) -> Option<usize> {
  let mut index = start + 1;
  let mut quote = 0u8;
  while index < bytes.len() {
    let byte = bytes[index];
    if quote != 0 {
      if byte == quote {
        quote = 0;
      }
    } else if byte == b'"' || byte == b'\'' {
      quote = byte;
    } else if byte == b'>' {
      return Some(index);
    }
    index += 1;
  }
  None
}

fn tag_name(tag: &str) -> &str {
  let rest = tag.trim_start_matches(['<', '/']).trim_start();
  let end = rest
    .find(|ch: char| ch.is_ascii_whitespace() || ch == '>' || ch == '/')
    .unwrap_or(rest.len());
  &rest[..end]
}

fn attr_value(tag: &str, name: &str) -> Option<String> {
  let bytes = tag.as_bytes();
  let name = name.as_bytes();
  let mut index = 0;
  while index + name.len() < bytes.len() {
    let matched = bytes[index..index + name.len()].eq_ignore_ascii_case(name)
      && (index == 0 || !bytes[index - 1].is_ascii_alphanumeric());
    if matched {
      let mut cursor = index + name.len();
      while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
        cursor += 1;
      }
      if cursor < bytes.len() && bytes[cursor] == b'=' {
        cursor += 1;
        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
          cursor += 1;
        }
        if cursor >= bytes.len() {
          return None;
        }
        let quote = bytes[cursor];
        if quote == b'"' || quote == b'\'' {
          let start = cursor + 1;
          let end = bytes[start..].iter().position(|byte| *byte == quote)? + start;
          return Some(tag[start..end].to_string());
        }
        let end = bytes[cursor..]
          .iter()
          .position(|byte| byte.is_ascii_whitespace() || *byte == b'>')
          .map(|position| cursor + position)
          .unwrap_or(bytes.len());
        return Some(tag[cursor..end].trim_end_matches('/').to_string());
      }
    }
    index += 1;
  }
  None
}

fn close_tag(bytes: &[u8], from: usize, name: &str) -> Option<usize> {
  let name = name.as_bytes();
  let mut index = from;
  while index + name.len() + 2 < bytes.len() {
    let matched = bytes[index] == b'<'
      && bytes[index + 1] == b'/'
      && bytes[index + 2..index + 2 + name.len()].eq_ignore_ascii_case(name)
      && !bytes[index + 2 + name.len()].is_ascii_alphanumeric();
    if matched {
      return Some(index);
    }
    index += 1;
  }
  None
}

fn decode_entities(text: &str) -> String {
  let bytes = text.as_bytes();
  let mut out = String::with_capacity(text.len());
  let mut index = 0;
  while index < bytes.len() {
    if bytes[index] != b'&' {
      let start = index;
      while index < bytes.len() && bytes[index] != b'&' {
        index += 1;
      }
      out.push_str(&text[start..index]);
      continue;
    }
    let Some(relative) = bytes[index + 1..].iter().position(|byte| *byte == b';') else {
      out.push('&');
      index += 1;
      continue;
    };
    let end = index + 1 + relative;
    if let Some(ch) = entity(&text[index + 1..end]) {
      out.push(ch);
      index = end + 1;
    } else {
      out.push('&');
      index += 1;
    }
  }
  out
}

fn entity(token: &str) -> Option<char> {
  match token {
    "amp" => Some('&'),
    "lt" => Some('<'),
    "gt" => Some('>'),
    "quot" => Some('"'),
    "apos" => Some('\''),
    "nbsp" => Some(' '),
    _ => numeric_entity(token),
  }
}

fn numeric_entity(token: &str) -> Option<char> {
  let hex = token.strip_prefix("#x").or_else(|| token.strip_prefix("#X"));
  let code = if let Some(hex) = hex {
    u32::from_str_radix(hex, 16).ok()?
  } else {
    token.strip_prefix('#')?.parse().ok()?
  };
  char::from_u32(code)
}

fn collapse_blank_lines(text: &str) -> String {
  let mut lines = Vec::new();
  let mut blank = false;
  for line in text.split('\n') {
    let line = line.trim_end();
    if line.is_empty() {
      if !blank && !lines.is_empty() {
        lines.push(String::new());
      }
      blank = true;
    } else {
      lines.push(line.to_string());
      blank = false;
    }
  }
  while lines.last().is_some_and(String::is_empty) {
    lines.pop();
  }
  lines.join("\n")
}

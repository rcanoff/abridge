//! Agent-facing shapes for framework providers. Swift still returns the framework projection;
//! this module is what an agent reads.

mod contacts;
mod eventkit;
mod location;
mod mapkit;
mod rank;
mod util;
mod vision;

// Notes calls these. Nothing else in this crate does until that wiring lands.
#[allow(unused_imports)]
pub use vision::{vision_markdown, vision_text};

use serde_json::{Map, Value, json};

use crate::tools::{
  TOOL_ACCEPT_INVITATION, TOOL_CALCULATE_ROUTE, TOOL_COMPLETE_REMINDER, TOOL_CREATE_CALENDAR, TOOL_CREATE_CONTACT,
  TOOL_CREATE_EVENT, TOOL_CREATE_GROUP, TOOL_CREATE_LIST, TOOL_CREATE_REMINDER, TOOL_DECLINE_INVITATION,
  TOOL_DELETE_CALENDAR, TOOL_DELETE_CONTACT, TOOL_DELETE_EVENT, TOOL_DELETE_GROUP, TOOL_DELETE_LIST,
  TOOL_DELETE_REMINDER, TOOL_DETECT_BARCODES, TOOL_DETECT_FACE_LANDMARKS, TOOL_ESTIMATE_TRAVEL_TIME,
  TOOL_FORWARD_GEOCODE, TOOL_GET_CONTACT, TOOL_GET_CURRENT_LOCATION, TOOL_GET_EVENT, TOOL_GET_PLACE, TOOL_GET_REMINDER,
  TOOL_GET_USAGE_LOG, TOOL_LINK_CONTACTS, TOOL_LIST_CALENDARS, TOOL_LIST_CONTACTS, TOOL_LIST_CONTAINERS,
  TOOL_LIST_EVENTS, TOOL_LIST_GROUPS, TOOL_LIST_LISTS, TOOL_LIST_REMINDERS, TOOL_MOVE_EVENT, TOOL_MOVE_REMINDER,
  TOOL_OPEN_NAVIGATION, TOOL_RECOGNIZE_DOCUMENTS, TOOL_RECOGNIZE_TEXT, TOOL_REVERSE_GEOCODE, TOOL_SEARCH_CONTACTS,
  TOOL_SEARCH_EVENTS, TOOL_SEARCH_NEARBY, TOOL_SEARCH_PLACES, TOOL_SEARCH_REMINDERS, TOOL_SET_EVENT_ALARMS,
  TOOL_SET_EVENT_RECURRENCE, TOOL_SET_REMINDER_ALARMS, TOOL_SET_REMINDER_RECURRENCE, TOOL_TENTATIVE_INVITATION,
  TOOL_UNCOMPLETE_REMINDER, TOOL_UNLINK_CONTACTS, TOOL_UPDATE_CALENDAR, TOOL_UPDATE_CONTACT, TOOL_UPDATE_EVENT,
  TOOL_UPDATE_GROUP, TOOL_UPDATE_REMINDER, ToolDefinition,
};

use util::{matches_json, slim};

pub struct Prepared {
  pub operation: String,
  pub payload_json: String,
  pub query: Option<String>,
  pub limit: Option<usize>,
  pub offset: usize,
  /// Agent-facing flag for the two Vision text tools. Stripped before the provider call.
  pub include_geometry: bool,
}

pub struct Shaped {
  pub text: String,
  pub images: Vec<Value>,
}

pub fn prepare(tool: &ToolDefinition, arguments: &Value) -> Prepared {
  let query = arguments
    .get("query")
    .and_then(Value::as_str)
    .filter(|query| query.split_whitespace().next().is_some())
    .map(str::to_string);
  let explicit_limit = arguments
    .get("limit")
    .and_then(Value::as_u64)
    .map(|limit| limit as usize);
  let offset = arguments.get("offset").and_then(Value::as_u64).unwrap_or(0) as usize;
  let ranks = matches!(
    tool.name,
    TOOL_SEARCH_CONTACTS | TOOL_SEARCH_EVENTS | TOOL_SEARCH_REMINDERS
  );
  let pages = lists_page(tool.name);
  let limit = if pages || (ranks && (query.is_some() || explicit_limit.is_some() || offset > 0)) {
    Some(explicit_limit.unwrap_or(50).clamp(1, 200))
  } else {
    explicit_limit.map(|limit| limit.clamp(1, 200))
  };

  if tool.name == TOOL_SEARCH_CONTACTS && query.is_some() {
    let mut payload = Map::new();
    if let Some(container) = arguments.get("container_identifier").and_then(Value::as_str)
      && !container.is_empty()
    {
      payload.insert("container_identifier".into(), Value::String(container.to_string()));
    }
    return Prepared {
      operation: "list_contacts".into(),
      payload_json: Value::Object(payload).to_string(),
      query,
      limit,
      offset,
      include_geometry: include_geometry(arguments),
    };
  }

  // List has no date predicate. A due window or completion filter uses the search predicate.
  if tool.name == TOOL_LIST_REMINDERS && reminder_predicate_requested(arguments) {
    return Prepared {
      operation: "search_reminders".into(),
      payload_json: provider_payload(tool.name, arguments),
      query: None,
      limit,
      offset,
      include_geometry: include_geometry(arguments),
    };
  }

  Prepared {
    operation: tool.operation.to_string(),
    payload_json: provider_payload(tool.name, arguments),
    query,
    limit,
    offset,
    include_geometry: include_geometry(arguments),
  }
}

fn include_geometry(arguments: &Value) -> bool {
  arguments.get("include_geometry").and_then(Value::as_bool) == Some(true)
}

pub fn shape(tool_name: &str, prepared: &Prepared, payload_json: &str) -> Shaped {
  let Ok(value) = serde_json::from_str::<Value>(payload_json) else {
    return Shaped {
      text: payload_json.to_string(),
      images: Vec::new(),
    };
  };
  let (shaped, images) = dispatch(tool_name, prepared, &value);
  let text = serde_json::to_string(&shaped).unwrap_or_else(|_| payload_json.to_string());
  Shaped { text, images }
}

/// Usage-log entries keep `success` and `logging_enabled` even when false. Other nulls drop.
pub fn shape_usage_log(value: &Value) -> Value {
  slim_keep_bools(value)
}

fn dispatch(tool_name: &str, prepared: &Prepared, value: &Value) -> (Value, Vec<Value>) {
  let shaped = match tool_name {
    TOOL_LIST_CALENDARS | TOOL_LIST_LISTS => map_items(value, eventkit::calendar_summary),
    TOOL_CREATE_CALENDAR | TOOL_UPDATE_CALENDAR | TOOL_CREATE_LIST => eventkit::calendar_summary(value),
    TOOL_LIST_EVENTS => page_items(value, prepared, eventkit::event_summary),
    TOOL_SEARCH_EVENTS => ranked(value, prepared, eventkit::event_fields, eventkit::event_summary),
    TOOL_GET_EVENT
    | TOOL_CREATE_EVENT
    | TOOL_UPDATE_EVENT
    | TOOL_MOVE_EVENT
    | TOOL_SET_EVENT_ALARMS
    | TOOL_SET_EVENT_RECURRENCE
    | TOOL_ACCEPT_INVITATION
    | TOOL_DECLINE_INVITATION
    | TOOL_TENTATIVE_INVITATION => eventkit::event_detail(value),
    TOOL_LIST_REMINDERS => page_items(value, prepared, eventkit::reminder_summary),
    TOOL_SEARCH_REMINDERS => ranked(value, prepared, eventkit::reminder_fields, eventkit::reminder_summary),
    TOOL_GET_REMINDER
    | TOOL_CREATE_REMINDER
    | TOOL_UPDATE_REMINDER
    | TOOL_MOVE_REMINDER
    | TOOL_COMPLETE_REMINDER
    | TOOL_UNCOMPLETE_REMINDER
    | TOOL_SET_REMINDER_ALARMS
    | TOOL_SET_REMINDER_RECURRENCE => eventkit::reminder_detail(value),
    TOOL_LIST_CONTACTS => page_items(value, prepared, contacts::summary),
    TOOL_SEARCH_CONTACTS => ranked(value, prepared, contacts::fields, contacts::summary),
    TOOL_LIST_GROUPS => page_items(value, prepared, contacts::group),
    TOOL_LIST_CONTAINERS => map_items(value, contacts::container),
    TOOL_CREATE_GROUP | TOOL_UPDATE_GROUP => contacts::group(value),
    TOOL_GET_CONTACT | TOOL_CREATE_CONTACT | TOOL_UPDATE_CONTACT | TOOL_LINK_CONTACTS | TOOL_UNLINK_CONTACTS => {
      let (detail, images) = contacts::detail(value);
      return (detail, images);
    }
    TOOL_SEARCH_PLACES | TOOL_SEARCH_NEARBY | TOOL_REVERSE_GEOCODE | TOOL_FORWARD_GEOCODE => {
      mapkit::search_response(value)
    }
    TOOL_GET_PLACE => mapkit::detail(value),
    TOOL_CALCULATE_ROUTE => mapkit::route_response(value, &request_arguments(prepared)),
    TOOL_ESTIMATE_TRAVEL_TIME => mapkit::travel_time(value, &request_arguments(prepared)),
    TOOL_OPEN_NAVIGATION => mapkit::navigation(value, &request_arguments(prepared)),
    TOOL_GET_CURRENT_LOCATION => location::current_location(value),
    TOOL_RECOGNIZE_TEXT => vision::shape_text(value, prepared.include_geometry),
    TOOL_RECOGNIZE_DOCUMENTS => vision::shape_documents(value, prepared.include_geometry),
    TOOL_DETECT_BARCODES | TOOL_DETECT_FACE_LANDMARKS => vision::shape(value),
    TOOL_GET_USAGE_LOG => shape_usage_log(value),
    TOOL_DELETE_CALENDAR | TOOL_DELETE_EVENT | TOOL_DELETE_LIST | TOOL_DELETE_REMINDER | TOOL_DELETE_CONTACT
    | TOOL_DELETE_GROUP => slim(value).unwrap_or_else(|| json!({})),
    _ => slim(value).unwrap_or_else(|| value.clone()),
  };
  (shaped, Vec::new())
}

fn request_arguments(prepared: &Prepared) -> Value {
  serde_json::from_str(&prepared.payload_json).unwrap_or(Value::Null)
}

fn map_items(value: &Value, summary: impl Fn(&Value) -> Value) -> Value {
  match value {
    Value::Array(items) => Value::Array(items.iter().map(summary).collect()),
    other => summary(other),
  }
}

fn lists_page(name: &str) -> bool {
  matches!(
    name,
    TOOL_LIST_EVENTS | TOOL_LIST_REMINDERS | TOOL_LIST_CONTACTS | TOOL_LIST_GROUPS
  )
}

fn provider_payload(tool_name: &str, arguments: &Value) -> String {
  let mut payload = arguments.clone();
  if let Some(object) = payload.as_object_mut() {
    if lists_page(tool_name) || tool_name == TOOL_SEARCH_EVENTS || tool_name == TOOL_SEARCH_REMINDERS {
      object.remove("limit");
      object.remove("offset");
    }
    if tool_name == TOOL_SEARCH_EVENTS || (tool_name == TOOL_DELETE_EVENT && object.contains_key("event_title")) {
      fill_event_search_window(object);
    }
    if tool_name == TOOL_LIST_REMINDERS || tool_name == TOOL_SEARCH_REMINDERS {
      normalize_reminder_window(object);
    }
    if tool_name == TOOL_RECOGNIZE_TEXT || tool_name == TOOL_RECOGNIZE_DOCUMENTS {
      object.remove("include_geometry");
    }
  }
  serde_json::to_string(&payload).unwrap_or_else(|_| "{}".into())
}

fn reminder_predicate_requested(arguments: &Value) -> bool {
  let Some(object) = arguments.as_object() else {
    return false;
  };
  [
    "completion_status",
    "due_date_starting",
    "due_date_ending",
    "completion_date_starting",
    "completion_date_ending",
    "include_overdue",
  ]
  .into_iter()
  .any(|key| object.contains_key(key))
}

/// `include_overdue` drops the due start so reminders due before that bound are included.
/// A due window without a completion status is incomplete; EventKit's due predicate is incomplete-only.
fn normalize_reminder_window(object: &mut Map<String, Value>) {
  let include_overdue = object.get("include_overdue").and_then(Value::as_bool) == Some(true);
  object.remove("include_overdue");
  if include_overdue {
    object.remove("due_date_starting");
    let status = object.get("completion_status").and_then(Value::as_str);
    if status.is_none() || status == Some("all") {
      object.insert("completion_status".into(), Value::String("incomplete".into()));
    }
  }
  let has_due = object.contains_key("due_date_starting") || object.contains_key("due_date_ending");
  if has_due && !object.contains_key("completion_status") {
    object.insert("completion_status".into(), Value::String("incomplete".into()));
  }
}

fn fill_event_search_window(object: &mut Map<String, Value>) {
  let has_start = object
    .get("start_date")
    .and_then(Value::as_str)
    .is_some_and(|text| !text.is_empty());
  let has_end = object
    .get("end_date")
    .and_then(Value::as_str)
    .is_some_and(|text| !text.is_empty());
  if has_start && has_end {
    return;
  }
  let now = std::time::SystemTime::now()
    .duration_since(std::time::UNIX_EPOCH)
    .map(|duration| duration.as_secs() as i64)
    .unwrap_or(0);
  let (default_start, default_end) = eventkit::event_search_bounds(now);
  let mut start = if has_start {
    object
      .get("start_date")
      .and_then(Value::as_str)
      .and_then(eventkit::parse_iso_unix)
      .unwrap_or(default_start)
  } else {
    default_start
  };
  let mut end = if has_end {
    object
      .get("end_date")
      .and_then(Value::as_str)
      .and_then(eventkit::parse_iso_unix)
      .unwrap_or(default_end)
  } else {
    default_end
  };
  // EventKit's event predicate returns nothing for a span of four years or more.
  const MAX_SPAN: i64 = (4 * 365 - 1) * 86_400;
  if !has_start && end.saturating_sub(start) > MAX_SPAN {
    start = end.saturating_sub(MAX_SPAN);
  }
  if !has_end && end.saturating_sub(start) > MAX_SPAN {
    end = start.saturating_add(MAX_SPAN);
  }
  if !has_start {
    object.insert("start_date".into(), Value::String(eventkit::format_unix_utc(start)));
  }
  if !has_end {
    object.insert("end_date".into(), Value::String(eventkit::format_unix_utc(end)));
  }
}

fn page_items(value: &Value, prepared: &Prepared, summary: impl Fn(&Value) -> Value) -> Value {
  match value {
    Value::Array(items) => Value::Array(page(items.iter().map(summary).collect(), prepared)),
    other => summary(other),
  }
}

fn ranked(
  value: &Value,
  prepared: &Prepared,
  fields: impl Fn(&Value) -> Vec<rank::OwnedField>,
  summary: impl Fn(&Value) -> Value,
) -> Value {
  let Some(items) = value.as_array() else {
    return summary(value);
  };
  if let Some(query) = &prepared.query {
    let limit = prepared.limit.unwrap_or(50);
    let hits = rank::rank(items, query, fields, prepared.offset, limit);
    return Value::Array(
      hits
        .into_iter()
        .map(|(index, score, matches)| {
          let mut object = match summary(&items[index]) {
            Value::Object(object) => object,
            other => return other,
          };
          object.insert("score".into(), Value::from(score));
          if !matches.is_empty() {
            object.insert("matches".into(), matches_json(&matches));
          }
          Value::Object(object)
        })
        .collect(),
    );
  }

  let summaries: Vec<Value> = items.iter().map(summary).collect();
  Value::Array(page(summaries, prepared))
}

fn page(items: Vec<Value>, prepared: &Prepared) -> Vec<Value> {
  let skipped = items.into_iter().skip(prepared.offset);
  match prepared.limit {
    Some(limit) => skipped.take(limit).collect(),
    None => skipped.collect(),
  }
}

fn slim_keep_bools(value: &Value) -> Value {
  match value {
    Value::Null => Value::Null,
    Value::Array(items) => Value::Array(
      items
        .iter()
        .map(slim_keep_bools)
        .filter(|item| !item.is_null())
        .collect(),
    ),
    Value::Object(map) => {
      let mut object = Map::new();
      for (key, item) in map {
        if item.is_null() {
          continue;
        }
        if let Value::String(text) = item
          && text.is_empty()
        {
          continue;
        }
        let shaped = match item {
          Value::Object(_) | Value::Array(_) => slim_keep_bools(item),
          other => other.clone(),
        };
        if !shaped.is_null() {
          object.insert(key.clone(), shaped);
        }
      }
      Value::Object(object)
    }
    other => other.clone(),
  }
}

#[cfg(test)]
mod tests {
  use super::{prepare, shape};
  use crate::tools::{self, ToolDefinition};
  use serde_json::json;

  fn tool(name: &str) -> ToolDefinition {
    *tools::all_tools().iter().find(|tool| tool.name == name).expect(name)
  }

  fn shaped(name: &str, payload: serde_json::Value) -> serde_json::Value {
    let definition = tool(name);
    let arguments = json!({});
    let prepared = prepare(&definition, &arguments);
    let outcome = shape(name, &prepared, &payload.to_string());
    serde_json::from_str(&outcome.text).expect("json")
  }

  #[test]
  fn event_summary_drops_framework_noise_and_is_smaller() {
    let raw = json!({
      "event_identifier": "evt-1",
      "calendar_item_identifier": "item-1",
      "calendar_item_external_identifier": "external-sync-id",
      "title": "Team Standup",
      "location": null,
      "url": null,
      "notes": "Discuss the roadmap and the blockers from yesterday's review.",
      "creation_date": "2023-11-14T22:13:20Z",
      "last_modified_date": "2023-11-14T22:13:20Z",
      "has_alarms": false,
      "has_recurrence_rules": false,
      "has_notes": true,
      "has_attendees": true,
      "time_zone": null,
      "attendees": [{
        "url": "mailto:a@example.com",
        "name": "Ada",
        "participant_status": "accepted",
        "participant_role": "required",
        "participant_type": "person",
        "is_current_user": false,
        "contact_predicate": "email == \"a@example.com\""
      }],
      "calendar": {
        "calendar_identifier": "cal-1",
        "title": "Work",
        "type": "caldav",
        "cg_color": { "components": [0.1, 0.2, 0.3, 1.0], "alpha": 1, "color_space_model": "rgb" },
        "allowed_entity_types": ["event"],
        "supported_event_availabilities": ["busy"],
        "allows_content_modifications": true,
        "is_immutable": false,
        "is_subscribed": false,
        "source": { "source_identifier": "src", "title": "iCloud", "source_type": "caldav" }
      },
      "start_date": "2023-11-14T15:00:00Z",
      "end_date": "2023-11-14T15:30:00Z",
      "is_all_day": false,
      "occurrence_date": "2023-11-14T15:00:00Z",
      "is_detached": false,
      "status": "confirmed",
      "organizer": null,
      "structured_location": null,
      "alarms": null,
      "recurrence_rules": null
    });
    let raw_len = raw.to_string().len();
    let summary = shaped(tools::TOOL_LIST_EVENTS, json!([raw]));
    let summary_len = summary.to_string().len();
    assert!(summary_len * 2 < raw_len, "summary {summary_len} raw {raw_len}");
    let event = &summary[0];
    assert_eq!(event["event_identifier"], "evt-1");
    assert_eq!(event["title"], "Team Standup");
    assert_eq!(event["calendar"]["title"], "Work");
    assert!(event.get("calendar_item_external_identifier").is_none());
    assert!(event.get("attendees").is_none());
    assert!(event.get("snippet").is_some());
    assert!(event.get("is_all_day").is_none());

    let detail = shaped(tools::TOOL_GET_EVENT, raw);
    assert!(detail.get("contact_predicate").is_none());
    assert!(detail["attendees"][0].get("contact_predicate").is_none());
    assert_eq!(detail["attendees"][0]["name"], "Ada");
    assert_eq!(
      detail["notes"],
      "Discuss the roadmap and the blockers from yesterday's review."
    );
    assert!(detail.get("calendar_item_external_identifier").is_none());
    assert_eq!(detail["calendar"]["color"], "#1A334D");
    assert!(detail.to_string().len() < raw_len);
  }

  #[test]
  fn search_events_ranks_fuzzy_matches_and_skips_misses() {
    let payload = json!([
      { "event_identifier": "evt-1", "title": "Team Standup", "notes": "daily", "calendar": { "calendar_identifier": "cal", "title": "Work" } },
      { "event_identifier": "evt-2", "title": "Lunch", "calendar": { "calendar_identifier": "cal", "title": "Work" } }
    ]);
    let definition = tool(tools::TOOL_SEARCH_EVENTS);
    let prepared = prepare(&definition, &json!({"query": "stndup"}));
    assert_eq!(prepared.operation, "search_events");
    let outcome = shape(tools::TOOL_SEARCH_EVENTS, &prepared, &payload.to_string());
    let hits: serde_json::Value = serde_json::from_str(&outcome.text).unwrap();
    assert_eq!(hits.as_array().unwrap().len(), 1);
    assert_eq!(hits[0]["event_identifier"], "evt-1");
    assert_eq!(hits[0]["matches"][0]["field"], "title");
    assert!(outcome.images.is_empty());
  }

  #[test]
  fn contact_list_strips_image_bytes_and_get_emits_image_content() {
    let mut jpeg_bytes = vec![0xFF, 0xD8, 0xFF, 0x00];
    jpeg_bytes.extend(std::iter::repeat_n(1u8, 3000));
    let jpeg = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &jpeg_bytes);
    let raw = json!({
      "identifier": "c-1",
      "contact_type": "person",
      "given_name": "Ada",
      "family_name": "Lovelace",
      "middle_name": "",
      "organization_name": "",
      "container_identifier": "local",
      "job_title": "Mathematician",
      "note": null,
      "image_data_available": true,
      "image_data": jpeg.clone(),
      "thumbnail_image_data": jpeg,
      "phone_numbers": [{ "label": "mobile", "identifier": "p1", "value": { "string_value": "555-0100" } }],
      "email_addresses": [{ "label": "work", "identifier": "e1", "value": "ada@example.com" }],
      "postal_addresses": [],
      "birthday": { "year": 1815, "month": 12, "day": 10, "hour": null, "calendar": { "identifier": "gregorian" } }
    });
    let raw_len = raw.to_string().len();
    let listed = shaped(tools::TOOL_LIST_CONTACTS, json!([raw.clone()]));
    let listed_len = listed.to_string().len();
    assert!(listed_len * 4 < raw_len, "list {listed_len} raw {raw_len}");
    assert_eq!(listed[0]["name"], "Ada Lovelace");
    assert_eq!(listed[0]["phone"], "555-0100");
    assert_eq!(listed[0]["email"], "ada@example.com");
    assert_eq!(listed[0]["container_identifier"], "local");
    assert!(listed[0].get("image_data").is_none());
    assert!(listed[0].get("thumbnail_image_data").is_none());
    assert_eq!(listed[0]["image_data_available"], true);

    let definition = tool(tools::TOOL_GET_CONTACT);
    let prepared = prepare(&definition, &json!({"contact_identifier": "c-1"}));
    let outcome = shape(tools::TOOL_GET_CONTACT, &prepared, &raw.to_string());
    let detail: serde_json::Value = serde_json::from_str(&outcome.text).unwrap();
    assert!(detail.get("image_data").is_none());
    assert_eq!(detail["container_identifier"], "local");
    assert_eq!(detail["phone_numbers"][0]["value"], "555-0100");
    assert_eq!(detail["email_addresses"][0]["value"], "ada@example.com");
    assert_eq!(detail["birthday"]["year"], 1815);
    assert!(detail["birthday"].get("calendar").is_none());
    assert_eq!(outcome.images.len(), 1);
    assert_eq!(outcome.images[0]["type"], "image");
    assert_eq!(outcome.images[0]["mimeType"], "image/jpeg");
    assert!(detail.to_string().len() * 4 < raw_len);
  }

  #[test]
  fn contact_query_lists_then_ranks_name_email_and_phone() {
    let definition = tool(tools::TOOL_SEARCH_CONTACTS);
    let prepared = prepare(
      &definition,
      &json!({"query": "ada", "container_identifier": "box", "name": "ignored"}),
    );
    assert_eq!(prepared.operation, "list_contacts");
    assert_eq!(prepared.payload_json, r#"{"container_identifier":"box"}"#);
    let payload = json!([
      {
        "identifier": "c-1",
        "given_name": "Ada",
        "family_name": "Lovelace",
        "container_identifier": "local",
        "email_addresses": [{ "value": "ada@example.com" }, { "value": "other@example.com" }],
        "phone_numbers": [{ "value": { "string_value": "555-0100" } }, { "value": { "string_value": "555-0199" } }]
      },
      { "identifier": "c-2", "given_name": "Grace", "family_name": "Hopper" }
    ]);
    let outcome = shape(tools::TOOL_SEARCH_CONTACTS, &prepared, &payload.to_string());
    let hits: serde_json::Value = serde_json::from_str(&outcome.text).unwrap();
    assert_eq!(hits.as_array().unwrap().len(), 1);
    assert_eq!(hits[0]["identifier"], "c-1");
    assert_eq!(hits[0]["email"], "ada@example.com");
    assert_eq!(hits[0]["phone"], "555-0100");
    assert_eq!(hits[0]["container_identifier"], "local");
    assert!(hits[0].get("email_addresses").is_none());
    assert!(hits[0].get("matches").is_some());
  }

  #[test]
  fn contact_containers_keep_only_the_default_flag() {
    let listed = shaped(
      tools::TOOL_LIST_CONTAINERS,
      json!([
        { "identifier": "local", "name": "On My Mac", "type": "local", "is_default": false },
        { "identifier": "icloud", "name": "iCloud", "type": "carddav", "is_default": true }
      ]),
    );
    assert_eq!(listed[0]["identifier"], "local");
    assert!(listed[0].get("is_default").is_none());
    assert_eq!(listed[1]["is_default"], true);
    assert_eq!(listed[1]["type"], "carddav");
  }

  #[test]
  fn reminder_query_keeps_the_predicate_call_and_ranks() {
    let definition = tool(tools::TOOL_SEARCH_REMINDERS);
    let prepared = prepare(
      &definition,
      &json!({"query": "milk", "completion_status": "incomplete"}),
    );
    assert_eq!(prepared.operation, "search_reminders");
    assert!(prepared.payload_json.contains("completion_status"));
    let payload = json!([
      { "calendar_item_identifier": "r-1", "title": "Buy milk", "is_completed": false, "priority": 0 },
      { "calendar_item_identifier": "r-2", "title": "Write report", "notes": "no dairy" }
    ]);
    let outcome = shape(tools::TOOL_SEARCH_REMINDERS, &prepared, &payload.to_string());
    let hits: serde_json::Value = serde_json::from_str(&outcome.text).unwrap();
    assert_eq!(hits[0]["calendar_item_identifier"], "r-1");
    assert!(hits[0].get("priority").is_none());
    assert!(hits[0].get("is_completed").is_none());
  }

  #[test]
  fn place_search_and_route_drop_placemark_and_polyline_noise() {
    let place = json!({
      "name": "Cafe",
      "phone_number": null,
      "url": "https://example.com",
      "time_zone": null,
      "point_of_interest_category": "cafe",
      "is_current_location": false,
      "identifier": "place-1",
      "location": {
        "coordinate": { "latitude": 1.5, "longitude": 2.5 },
        "altitude": 0,
        "horizontal_accuracy": -1,
        "vertical_accuracy": -1,
        "course": -1,
        "speed": -1,
        "timestamp": "2023-11-14T22:13:20Z",
        "floor": null
      },
      "placemark": {
        "coordinate": { "latitude": 1.5, "longitude": 2.5 },
        "altitude": 0,
        "ellipsoidal_altitude": 0,
        "inland_water": null,
        "ocean": null,
        "address_dictionary": { "Street": "1 Main" },
        "postal_address": { "street": "1 Main", "city": "Town", "state": "", "postal_code": null }
      },
      "address": { "full_address": "1 Main, Town", "short_address": null, "city": null },
      "address_representations": null
    });
    let raw_len = place.to_string().len();
    let listed = shaped(
      tools::TOOL_SEARCH_PLACES,
      json!({ "map_items": [place], "bounding_region": null }),
    );
    let listed_len = listed.to_string().len();
    assert!(listed_len < raw_len, "places {listed_len} raw {raw_len}");
    assert_eq!(listed["map_items"][0]["name"], "Cafe");
    assert_eq!(listed["map_items"][0]["coordinate"]["latitude"], 1.5);
    assert_eq!(listed["map_items"][0]["address"], "1 Main, Town");
    assert!(listed.get("bounding_region").is_none());
    assert!(listed["map_items"][0].get("placemark").is_none());

    let route = json!({
      "source": place_stub("A"),
      "destination": place_stub("B"),
      "routes": [{
        "name": "Via Main",
        "advisory_notices": [],
        "distance": 1200,
        "expected_travel_time": 300,
        "transport_type": ["automobile"],
        "polyline": { "title": null, "point_count": 3, "coordinates": [{"latitude": 1, "longitude": 2}, {"latitude": 3, "longitude": 4}, {"latitude": 5, "longitude": 6}] },
        "steps": [{ "instructions": "Turn left", "notice": null, "distance": 40, "transport_type": ["automobile"], "polyline": { "coordinates": [{"latitude": 1, "longitude": 2}] } }],
        "has_tolls": false,
        "has_highways": true
      }]
    });
    let route_raw = route.to_string().len();
    let shaped_route = shaped(tools::TOOL_CALCULATE_ROUTE, route);
    assert!(shaped_route.to_string().len() < route_raw);
    assert!(shaped_route["routes"][0].get("polyline").is_none());
    assert_eq!(shaped_route["routes"][0]["steps"][0]["instructions"], "Turn left");
    assert_eq!(shaped_route["routes"][0]["has_highways"], true);
    assert!(shaped_route["routes"][0].get("has_tolls").is_none());
  }

  #[test]
  fn travel_time_uses_request_place_names_and_drops_unknown_location() {
    let definition = tool(tools::TOOL_ESTIMATE_TRAVEL_TIME);
    let prepared = prepare(
      &definition,
      &json!({
        "source": {
          "coordinate": { "latitude": 38.77, "longitude": -9.13 },
          "name": "Humberto Delgado Airport"
        },
        "destination": {
          "coordinate": { "latitude": 38.69, "longitude": -9.22 },
          "identifier": "place-tower"
        }
      }),
    );
    let payload = json!({
      "source": {
        "name": "Unknown Location",
        "location": { "coordinate": { "latitude": 38.77, "longitude": -9.13 } }
      },
      "destination": {
        "name": "Unknown Location",
        "location": { "coordinate": { "latitude": 38.69, "longitude": -9.22 } }
      },
      "expected_travel_time": 1080,
      "distance": 9000
    });
    let outcome = shape(tools::TOOL_ESTIMATE_TRAVEL_TIME, &prepared, &payload.to_string());
    let value: serde_json::Value = serde_json::from_str(&outcome.text).unwrap();
    assert_eq!(value["source"]["name"], "Humberto Delgado Airport");
    assert!(value["destination"].get("name").is_none());
    assert_eq!(value["destination"]["identifier"], "place-tower");
    assert_eq!(value["expected_travel_time"], 1080);
  }

  #[test]
  fn travel_time_keeps_reverse_geocoded_name() {
    let value = shaped(
      tools::TOOL_ESTIMATE_TRAVEL_TIME,
      json!({
        "source": {
          "name": "Torre de Belém",
          "location": { "coordinate": { "latitude": 38.69, "longitude": -9.22 } }
        },
        "destination": {
          "name": "Unknown Location",
          "location": { "coordinate": { "latitude": 38.77, "longitude": -9.13 } }
        },
        "expected_travel_time": 600
      }),
    );
    assert_eq!(value["source"]["name"], "Torre de Belém");
    assert!(value["destination"].get("name").is_none());
  }

  fn place_stub(name: &str) -> serde_json::Value {
    json!({
      "name": name,
      "location": { "coordinate": { "latitude": 1.0, "longitude": 2.0 } },
      "is_current_location": false
    })
  }

  #[test]
  fn vision_and_location_drop_masks_and_invalid_readings() {
    let mask = "A".repeat(2000);
    let vision = json!({
      "results": [{
        "uuid": "abc",
        "confidence": 0.9,
        "time_range": { "start_seconds": 0, "duration_seconds": 0 },
        "request_revision": 1,
        "bounding_box": { "origin": { "x": 0.1, "y": 0.2 }, "size": { "width": 0.3, "height": 0.4 } },
        "global_segmentation_mask": { "pixel_buffer": { "data": mask, "width": 8, "height": 8 } },
        "top_left": { "x": 0, "y": 1 },
        "candidates": [{ "string": "Hello", "confidence": 0.8, "request_revision": 1 }]
      }]
    });
    let raw_len = vision.to_string().len();
    assert_eq!(super::vision_text(&vision), "Hello");
    assert_eq!(super::vision_markdown(&json!({ "results": [] })), "");
    let text = shaped(tools::TOOL_RECOGNIZE_TEXT, vision.clone());
    assert!(
      text.to_string().len() * 2 < raw_len,
      "vision {} raw {raw_len}",
      text.to_string().len()
    );
    assert_eq!(text["text"], "Hello");
    assert!(text.get("results").is_none());
    assert!(text.get("page").is_none());
    assert!(text.get("page_count").is_none());

    let prepared = prepare(
      &tool(tools::TOOL_RECOGNIZE_TEXT),
      &json!({ "image_path": "/tmp/page.png", "include_geometry": true }),
    );
    assert!(prepared.include_geometry);
    assert!(!prepared.payload_json.contains("include_geometry"));
    let detailed = shape(tools::TOOL_RECOGNIZE_TEXT, &prepared, &vision.to_string());
    let detailed: serde_json::Value = serde_json::from_str(&detailed.text).expect("json");
    assert_eq!(detailed["text"], "Hello");
    assert_eq!(detailed["results"][0]["candidates"][0]["string"], "Hello");
    assert!(detailed["results"][0].get("uuid").is_none());
    assert!(detailed["results"][0].get("global_segmentation_mask").is_none());
    assert!(detailed["results"][0].get("top_left").is_none());

    let pdf = shaped(
      tools::TOOL_RECOGNIZE_TEXT,
      json!({
        "results": [{ "candidates": [{ "string": "PAGETWO", "confidence": 0.9 }] }],
        "page": 2,
        "page_count": 2
      }),
    );
    assert_eq!(pdf["text"], "PAGETWO");
    assert_eq!(pdf["page"], 2);
    assert_eq!(pdf["page_count"], 2);
    assert!(pdf.get("results").is_none());

    let location = shaped(
      tools::TOOL_GET_CURRENT_LOCATION,
      json!({
        "location": {
          "coordinate": { "latitude": 28.8, "longitude": -81.6 },
          "altitude": 30.0,
          "horizontal_accuracy": 5.0,
          "vertical_accuracy": -1.0,
          "course": -1.0,
          "speed": -1.0,
          "timestamp": "2023-11-14T22:13:20Z",
          "floor": null
        }
      }),
    );
    assert_eq!(location["location"]["coordinate"]["latitude"], 28.8);
    assert!(location["location"].get("course").is_none());
    assert!(location["location"].get("speed").is_none());
    assert!(location["location"].get("floor").is_none());
    assert_eq!(location["location"]["horizontal_accuracy"], 5.0);
  }

  #[test]
  fn usage_log_keeps_failed_success_and_drops_nulls() {
    let value = shape_usage_log_value();
    assert_eq!(value["logging_enabled"], false);
    assert_eq!(value["entries"][0]["success"], false);
    assert!(value["entries"][0].get("tool_name").is_none());
    assert!(value["entries"][0].get("duration_ms").is_none());
  }

  fn shape_usage_log_value() -> serde_json::Value {
    super::shape_usage_log(&json!({
      "logging_enabled": false,
      "entries": [{
        "timestamp_utc": "2023-11-14T22:13:20.000Z",
        "event_type": "tool_call",
        "tool_name": null,
        "success": false,
        "duration_ms": null
      }]
    }))
  }
  #[test]
  fn contact_labels_become_plain_words_and_custom_labels_pass_through() {
    let detail = shaped(
      tools::TOOL_GET_CONTACT,
      json!({
        "identifier": "c-1",
        "given_name": "Ada",
        "phone_numbers": [
          { "label": "_$!<Mobile>!$_", "value": { "string_value": "555-0100" } },
          { "label": "_$!<HomeFAX>!$_", "value": { "string_value": "555-0199" } },
          { "label": "iPhone", "value": { "string_value": "555-0101" } },
          { "label": "Mom", "value": { "string_value": "555-0102" } }
        ],
        "email_addresses": [
          { "label": "_$!<Home>!$_", "value": "home@example.com" },
          { "label": "_$!<Other>!$_", "value": "other@example.com" },
          { "label": "iCloud", "value": "ada@icloud.com" }
        ],
        "url_addresses": [{ "label": "_$!<HomePage>!$_", "value": "https://example.com" }],
        "contact_relations": [{ "label": "_$!<GirlfriendOrBoyfriend>!$_", "value": { "name": "Pat" } }]
      }),
    );
    let phones = detail["phone_numbers"].as_array().unwrap();
    assert_eq!(phones[0]["label"], "mobile");
    assert_eq!(phones[0]["value"], "555-0100");
    assert_eq!(phones[1]["label"], "home fax");
    assert_eq!(phones[2]["label"], "iphone");
    assert_eq!(phones[3]["label"], "Mom");
    assert_eq!(detail["email_addresses"][0]["label"], "home");
    assert_eq!(detail["email_addresses"][1]["label"], "other");
    assert_eq!(detail["email_addresses"][2]["label"], "icloud");
    assert_eq!(detail["url_addresses"][0]["label"], "home page");
    assert_eq!(detail["contact_relations"][0]["label"], "girlfriend or boyfriend");
  }

  #[test]
  fn event_notes_become_markdown_and_detail_keeps_only_event_identifier() {
    let raw = json!({
      "event_identifier": "evt-1",
      "calendar_item_identifier": "item-1",
      "title": "Sync",
      "notes": "Join here<br /><a href=\"https://example.com?a=1&amp;b=2\">room</a><br /><br /><br /><b>Bring notes</b>",
      "calendar": {
        "calendar_identifier": "cal-1",
        "title": "Work",
        "source": { "source_identifier": "src-events", "title": "iCloud", "source_type": "cal_dav" }
      }
    });
    let detail = shaped(tools::TOOL_GET_EVENT, raw.clone());
    assert_eq!(detail["event_identifier"], "evt-1");
    assert!(detail.get("calendar_item_identifier").is_none());
    assert_eq!(
      detail["notes"],
      "Join here\n[room](https://example.com?a=1&b=2)\n\nBring notes"
    );
    assert_eq!(detail["calendar"]["source"]["source_identifier"], "src-events");
    assert_eq!(detail["calendar"]["source"]["title"], "iCloud");
    assert_eq!(detail["calendar"]["source"]["type"], "cal_dav");
    assert!(detail["calendar"]["source"].get("source_type").is_none());

    let listed = shaped(tools::TOOL_LIST_EVENTS, json!([raw]));
    assert_eq!(
      listed[0]["snippet"],
      "Join here [room](https://example.com?a=1&b=2) Bring notes"
    );
    assert!(!listed[0]["snippet"].as_str().unwrap().contains("<a"));
  }

  #[test]
  fn reminder_dates_are_strings_and_writes_are_not_this_shape() {
    let detail = shaped(
      tools::TOOL_GET_REMINDER,
      json!({
        "calendar_item_identifier": "r-1",
        "title": "Pay",
        "due_date_components": {
          "year": 2027, "month": 3, "day": 24,
          "hour": null, "minute": null, "second": null,
          "time_zone": "America/New_York"
        },
        "start_date_components": {
          "year": 2027, "month": 3, "day": 24,
          "hour": 0, "minute": 0, "second": 0,
          "time_zone": "America/New_York"
        }
      }),
    );
    assert_eq!(detail["calendar_item_identifier"], "r-1");
    assert_eq!(detail["due_date"], "2027-03-24");
    assert_eq!(detail["start_date"], "2027-03-24T00:00:00-04:00");
    assert!(detail.get("floating").is_none());
    assert!(detail.get("due_date_components").is_none());
    assert!(detail.get("start_date_components").is_none());

    let winter = shaped(
      tools::TOOL_GET_REMINDER,
      json!({
        "calendar_item_identifier": "r-2",
        "due_date_components": {
          "year": 2027, "month": 1, "day": 15, "hour": 9, "minute": 30,
          "time_zone": "America/New_York"
        }
      }),
    );
    assert_eq!(winter["due_date"], "2027-01-15T09:30-05:00");
    assert!(winter.get("floating").is_none());

    let floating = shaped(
      tools::TOOL_GET_REMINDER,
      json!({
        "calendar_item_identifier": "r-3",
        "due_date_components": { "year": 2027, "month": 7, "day": 4, "hour": 9, "minute": 5, "second": 0 }
      }),
    );
    assert_eq!(floating["due_date"], "2027-07-04T09:05:00");
    assert_eq!(floating["floating"], true);
    assert!(floating.get("time_zone").is_none());

    let utc = shaped(
      tools::TOOL_GET_REMINDER,
      json!({
        "calendar_item_identifier": "r-4",
        "due_date_components": {
          "year": 2027, "month": 3, "day": 24, "hour": 12, "minute": 0, "second": 0, "time_zone": "UTC"
        }
      }),
    );
    assert_eq!(utc["due_date"], "2027-03-24T12:00:00Z");

    let kathmandu = shaped(
      tools::TOOL_GET_REMINDER,
      json!({
        "calendar_item_identifier": "r-5",
        "due_date_components": {
          "year": 2027, "month": 1, "day": 1, "hour": 0, "minute": 0, "time_zone": "Asia/Kathmandu"
        }
      }),
    );
    assert_eq!(kathmandu["due_date"], "2027-01-01T00:00+05:45");

    let item_zone = shaped(
      tools::TOOL_GET_REMINDER,
      json!({
        "calendar_item_identifier": "r-6",
        "time_zone": "America/Los_Angeles",
        "due_date_components": {
          "year": 2026, "month": 10, "day": 19, "hour": 9, "minute": 0,
          "time_zone": "America/New_York"
        }
      }),
    );
    assert_eq!(item_zone["due_date"], "2026-10-19T09:00-04:00");

    let fallback = shaped(
      tools::TOOL_GET_REMINDER,
      json!({
        "calendar_item_identifier": "r-7",
        "time_zone": "America/New_York",
        "due_date_components": { "year": 2026, "month": 10, "day": 19, "hour": 9, "minute": 0 }
      }),
    );
    assert_eq!(fallback["due_date"], "2026-10-19T09:00:00");
    assert_eq!(fallback["floating"], true);
    assert_eq!(fallback["time_zone"], "America/New_York");
  }

  #[test]
  fn event_sentinels_are_omitted_and_real_facts_stay() {
    let detail = shaped(
      tools::TOOL_GET_EVENT,
      json!({
        "event_identifier": "evt",
        "status": "none",
        "availability": "not_supported"
      }),
    );
    assert!(detail.get("status").is_none());
    assert!(detail.get("availability").is_none());

    let listed = shaped(
      tools::TOOL_LIST_EVENTS,
      json!([{ "event_identifier": "evt", "status": "none", "availability": "busy" }]),
    );
    assert!(listed[0].get("status").is_none());
    assert!(listed[0].get("availability").is_none());

    let kept = shaped(
      tools::TOOL_GET_EVENT,
      json!({
        "event_identifier": "evt",
        "status": "confirmed",
        "availability": "busy"
      }),
    );
    assert_eq!(kept["status"], "confirmed");
    assert_eq!(kept["availability"], "busy");
  }

  #[test]
  fn event_times_are_local_wall_time_with_offset() {
    let detail = shaped(
      tools::TOOL_GET_EVENT,
      json!({
        "event_identifier": "gym",
        "title": "Gym",
        "time_zone": "America/New_York",
        "start_date": "2026-10-19T22:00:00Z",
        "end_date": "2026-10-19T23:00:00Z",
        "occurrence_date": "2026-10-19T22:00:00Z"
      }),
    );
    assert_eq!(detail["start_date"], "2026-10-19T18:00:00-04:00");
    assert_eq!(detail["end_date"], "2026-10-19T19:00:00-04:00");
    assert_eq!(detail["occurrence_date"], "2026-10-19T18:00:00-04:00");
    assert_eq!(detail["time_zone"], "America/New_York");

    let winter = shaped(
      tools::TOOL_GET_EVENT,
      json!({
        "event_identifier": "gym",
        "time_zone": "America/New_York",
        "start_date": "2026-11-19T23:00:00Z",
        "end_date": "2026-11-20T00:00:00Z"
      }),
    );
    assert_eq!(winter["start_date"], "2026-11-19T18:00:00-05:00");

    let later = shaped(
      tools::TOOL_GET_EVENT,
      json!({
        "event_identifier": "later",
        "time_zone": "America/New_York",
        "start_date": "2100-07-15T16:00:00Z",
        "end_date": "2100-07-15T17:00:00Z"
      }),
    );
    assert_eq!(later["start_date"], "2100-07-15T12:00:00-04:00");
    assert_eq!(later["end_date"], "2100-07-15T13:00:00-04:00");

    let all_day = shaped(
      tools::TOOL_GET_EVENT,
      json!({
        "event_identifier": "off",
        "time_zone": "America/New_York",
        "is_all_day": true,
        "start_date": "2026-10-19T04:00:00Z",
        "end_date": "2026-10-20T04:00:00Z"
      }),
    );
    assert_eq!(all_day["start_date"], "2026-10-19");
    assert_eq!(all_day["end_date"], "2026-10-20");
    assert_eq!(all_day["is_all_day"], true);

    let west = shaped(
      tools::TOOL_GET_EVENT,
      json!({
        "event_identifier": "west",
        "time_zone": "America/Los_Angeles",
        "is_all_day": true,
        "start_date": "2026-10-19T07:00:00Z",
        "end_date": "2026-10-20T07:00:00Z"
      }),
    );
    assert_eq!(west["start_date"], "2026-10-19");
    assert_eq!(west["end_date"], "2026-10-20");

    let east = shaped(
      tools::TOOL_GET_EVENT,
      json!({
        "event_identifier": "east",
        "time_zone": "Asia/Tokyo",
        "is_all_day": true,
        "start_date": "2026-10-18T15:00:00Z",
        "end_date": "2026-10-19T15:00:00Z"
      }),
    );
    assert_eq!(east["start_date"], "2026-10-19");
    assert_eq!(east["end_date"], "2026-10-20");
    let system = shaped(
      tools::TOOL_CREATE_EVENT,
      json!({
        "event_identifier": "utc",
        "title": "Standup",
        "start_date": "2026-10-19T22:00:00Z",
        "end_date": "2026-10-19T22:30:00Z"
      }),
    );
    assert_eq!(system["start_date"], "2026-10-19T22:00:00Z");
    assert!(system.get("time_zone").is_none());

    let listed = shaped(
      tools::TOOL_LIST_EVENTS,
      json!([
        {
          "event_identifier": "gym",
          "title": "Gym",
          "time_zone": "America/New_York",
          "has_recurrence_rules": true,
          "start_date": "2026-10-19T22:00:00Z",
          "end_date": "2026-10-19T23:00:00Z"
        },
        {
          "event_identifier": "gym",
          "title": "Gym",
          "time_zone": "America/New_York",
          "has_recurrence_rules": true,
          "start_date": "2026-10-21T22:00:00Z",
          "end_date": "2026-10-21T23:00:00Z"
        }
      ]),
    );
    assert_eq!(listed[0]["event_identifier"], "gym");
    assert_eq!(listed[1]["event_identifier"], "gym");
    assert_eq!(listed[0]["start_date"], "2026-10-19T18:00:00-04:00");
    assert_eq!(listed[1]["start_date"], "2026-10-21T18:00:00-04:00");
    assert_eq!(listed[0]["time_zone"], "America/New_York");
    assert_eq!(listed[0]["has_recurrence_rules"], true);
  }

  #[test]
  fn search_events_without_dates_uses_a_three_year_window() {
    let definition = tool(tools::TOOL_SEARCH_EVENTS);
    let before = std::time::SystemTime::now()
      .duration_since(std::time::UNIX_EPOCH)
      .expect("clock")
      .as_secs() as i64;
    let prepared = prepare(&definition, &json!({"query": "gym"}));
    let after = std::time::SystemTime::now()
      .duration_since(std::time::UNIX_EPOCH)
      .expect("clock")
      .as_secs() as i64;
    assert_eq!(prepared.operation, "search_events");
    let payload: serde_json::Value = serde_json::from_str(&prepared.payload_json).unwrap();
    assert_eq!(payload["query"], "gym");
    assert!(payload.get("limit").is_none());
    let start = super::eventkit::parse_iso_unix(payload["start_date"].as_str().unwrap()).unwrap();
    let end = super::eventkit::parse_iso_unix(payload["end_date"].as_str().unwrap()).unwrap();
    let (low_start, _) = super::eventkit::event_search_bounds(before);
    let (_, high_end) = super::eventkit::event_search_bounds(after);
    let (_, low_end) = super::eventkit::event_search_bounds(before);
    let (high_start, _) = super::eventkit::event_search_bounds(after);
    assert!(start >= low_start && start <= high_start);
    assert!(end >= low_end && end <= high_end);
    assert!(end - start > 2 * 365 * 86_400);

    let kept = prepare(
      &definition,
      &json!({"query": "gym", "start_date": "2026-01-01T00:00:00Z", "end_date": "2026-02-01T00:00:00Z"}),
    );
    assert!(kept.payload_json.contains("2026-01-01T00:00:00Z"));
    assert!(kept.payload_json.contains("2026-02-01T00:00:00Z"));
  }

  #[test]
  fn delete_event_by_title_uses_the_search_window() {
    let definition = tool(tools::TOOL_DELETE_EVENT);
    let prepared = prepare(&definition, &json!({"event_title": "Standup"}));
    let payload: serde_json::Value = serde_json::from_str(&prepared.payload_json).unwrap();
    assert!(payload.get("start_date").and_then(|value| value.as_str()).is_some());
    assert!(payload.get("end_date").and_then(|value| value.as_str()).is_some());
    let kept = prepare(&definition, &json!({"event_identifier": "evt-1"}));
    let by_id: serde_json::Value = serde_json::from_str(&kept.payload_json).unwrap();
    assert!(by_id.get("start_date").is_none());
    assert!(by_id.get("end_date").is_none());
  }

  #[test]
  fn event_detail_keeps_weekday_names() {
    let detail = shaped(
      tools::TOOL_GET_EVENT,
      json!({
        "event_identifier": "evt-1",
        "title": "Standup",
        "recurrence_rules": [{
          "frequency": "weekly",
          "days_of_the_week": [{ "day_of_the_week": "monday", "week_number": 2 }]
        }]
      }),
    );
    assert_eq!(
      detail["recurrence_rules"][0]["days_of_the_week"][0]["day_of_the_week"],
      "monday"
    );
    assert_eq!(detail["recurrence_rules"][0]["days_of_the_week"][0]["week_number"], 2);
  }

  #[test]
  fn list_reminders_due_window_is_an_incomplete_predicate() {
    let definition = tool(tools::TOOL_LIST_REMINDERS);
    let prepared = prepare(
      &definition,
      &json!({
        "due_date_starting": "2026-10-19T00:00:00Z",
        "due_date_ending": "2026-10-22T00:00:00Z",
        "limit": 10
      }),
    );
    assert_eq!(prepared.operation, "search_reminders");
    assert_eq!(prepared.limit, Some(10));
    let payload: serde_json::Value = serde_json::from_str(&prepared.payload_json).unwrap();
    assert_eq!(payload["completion_status"], "incomplete");
    assert_eq!(payload["due_date_starting"], "2026-10-19T00:00:00Z");
    assert_eq!(payload["due_date_ending"], "2026-10-22T00:00:00Z");
    assert!(payload.get("limit").is_none());

    let overdue = prepare(
      &definition,
      &json!({
        "completion_status": "incomplete",
        "due_date_starting": "2026-10-19T00:00:00Z",
        "due_date_ending": "2026-10-22T00:00:00Z",
        "include_overdue": true
      }),
    );
    let overdue_payload: serde_json::Value = serde_json::from_str(&overdue.payload_json).unwrap();
    assert!(overdue_payload.get("due_date_starting").is_none());
    assert!(overdue_payload.get("include_overdue").is_none());
    assert_eq!(overdue_payload["due_date_ending"], "2026-10-22T00:00:00Z");
    assert_eq!(overdue_payload["completion_status"], "incomplete");

    let plain = prepare(&definition, &json!({"calendar_identifier": "list-1"}));
    assert_eq!(plain.operation, "list_reminders");
  }

  #[test]
  fn list_tools_page_after_shaping_and_do_not_forward_the_page() {
    let reminders = json!([
      { "calendar_item_identifier": "r-1", "title": "One" },
      { "calendar_item_identifier": "r-2", "title": "Two" },
      { "calendar_item_identifier": "r-3", "title": "Three" }
    ]);
    let definition = tool(tools::TOOL_LIST_REMINDERS);
    let prepared = prepare(
      &definition,
      &json!({ "calendar_identifier": "list-1", "limit": 1, "offset": 1 }),
    );
    assert_eq!(prepared.limit, Some(1));
    assert_eq!(prepared.offset, 1);
    assert_eq!(prepared.payload_json, r#"{"calendar_identifier":"list-1"}"#);
    let page = shape(tools::TOOL_LIST_REMINDERS, &prepared, &reminders.to_string());
    let rows: serde_json::Value = serde_json::from_str(&page.text).unwrap();
    assert_eq!(rows.as_array().unwrap().len(), 1);
    assert_eq!(rows[0]["calendar_item_identifier"], "r-2");

    let events = tool(tools::TOOL_LIST_EVENTS);
    let event_page = prepare(
      &events,
      &json!({ "start_date": "2026-01-01T00:00:00Z", "end_date": "2026-02-01T00:00:00Z", "limit": 2, "offset": 1 }),
    );
    assert!(!event_page.payload_json.contains("limit"));
    assert!(event_page.payload_json.contains("start_date"));
    let listed = shape(
      tools::TOOL_LIST_EVENTS,
      &event_page,
      &json!([
        { "event_identifier": "e-1", "title": "A" },
        { "event_identifier": "e-2", "title": "B" },
        { "event_identifier": "e-3", "title": "C" }
      ])
      .to_string(),
    );
    let event_rows: serde_json::Value = serde_json::from_str(&listed.text).unwrap();
    assert_eq!(event_rows.as_array().unwrap().len(), 2);
    assert_eq!(event_rows[0]["event_identifier"], "e-2");

    let contacts = tool(tools::TOOL_LIST_CONTACTS);
    let contact_page = prepare(&contacts, &json!({ "container_identifier": "box", "offset": 1 }));
    assert_eq!(contact_page.limit, Some(50));
    assert_eq!(contact_page.payload_json, r#"{"container_identifier":"box"}"#);
    let contact_rows = shape(
      tools::TOOL_LIST_CONTACTS,
      &contact_page,
      &json!([
        { "identifier": "c-1", "given_name": "Ada" },
        { "identifier": "c-2", "given_name": "Grace" }
      ])
      .to_string(),
    );
    let contacts_json: serde_json::Value = serde_json::from_str(&contact_rows.text).unwrap();
    assert_eq!(contacts_json.as_array().unwrap().len(), 1);
    assert_eq!(contacts_json[0]["identifier"], "c-2");

    let groups = tool(tools::TOOL_LIST_GROUPS);
    let group_page = prepare(&groups, &json!({ "limit": 1 }));
    assert_eq!(group_page.payload_json, "{}");
    let group_rows = shape(
      tools::TOOL_LIST_GROUPS,
      &group_page,
      &json!([{ "identifier": "g-1", "name": "Family" }, { "identifier": "g-2", "name": "Work" }]).to_string(),
    );
    let groups_json: serde_json::Value = serde_json::from_str(&group_rows.text).unwrap();
    assert_eq!(groups_json.as_array().unwrap().len(), 1);
    assert_eq!(groups_json[0]["identifier"], "g-1");
  }

  #[test]
  fn calendar_sources_stay_distinct_and_compact() {
    let listed = shaped(
      tools::TOOL_LIST_CALENDARS,
      json!([
        {
          "calendar_identifier": "cal-1",
          "title": "Work",
          "type": "cal_dav",
          "source": { "source_identifier": "icloud-events", "title": "iCloud", "source_type": "cal_dav", "extra": "drop" }
        },
        {
          "calendar_identifier": "list-1",
          "title": "Reminders",
          "type": "cal_dav",
          "source": { "source_identifier": "icloud-reminders", "title": "iCloud", "source_type": "cal_dav" }
        }
      ]),
    );
    assert_eq!(listed[0]["source"]["source_identifier"], "icloud-events");
    assert_eq!(listed[1]["source"]["source_identifier"], "icloud-reminders");
    assert_eq!(listed[0]["source"]["type"], "cal_dav");
    assert!(listed[0]["source"].get("extra").is_none());
    assert!(listed[0]["source"].get("source_type").is_none());
  }
}

//! One search across notes, reminders, and events.
//!
//! Notes runs in Rust. Reminders and events use the provider bridge, sequentially, because
//! EventKit is a single main-actor store. Notes runs beside that work. A store that fails or is
//! denied is reported in `store_errors`; the other stores are still returned.

use std::path::Path;
use std::thread;

use serde_json::{Map, Value, json};

use crate::agent_shape;
use crate::capabilities;
use crate::config::ProviderRequest;
use crate::providers::ProviderBridge;
use crate::tools::{self, TOOL_SEARCH_EVENTS, TOOL_SEARCH_REMINDERS};

const DEFAULT_LIMIT: u64 = 20;
const MAX_LIMIT: u64 = 100;
const STORES: [&str; 3] = ["notes", "reminders", "events"];

/// Search the enabled stores. `Err` is an invalid argument, not a store failure.
pub(super) fn search(
  arguments: &Value,
  enabled_capabilities: &[String],
  provider_enabled: impl Fn(&str) -> bool,
  provider: &dyn ProviderBridge,
  notes_store: Option<&Path>,
) -> Result<Value, String> {
  let query = arguments
    .get("query")
    .and_then(Value::as_str)
    .filter(|query| query.chars().any(|c| !c.is_whitespace()))
    .ok_or_else(|| "missing required property 'query'".to_string())?;
  let limit = arguments
    .get("limit")
    .and_then(Value::as_u64)
    .unwrap_or(DEFAULT_LIMIT)
    .clamp(1, MAX_LIMIT) as usize;
  let (requested, explicit) = requested_stores(arguments)?;

  let mut selected = Vec::new();
  let mut errors = Vec::new();
  for store in requested {
    let capability = store_capability(store);
    if !enabled_capabilities.iter().any(|enabled| enabled == capability) {
      if explicit {
        errors.push(store_error(
          store,
          "capability_disabled",
          format!("capability not enabled: {capability}"),
        ));
      }
      continue;
    }
    let provider_name = store_provider(store);
    if !provider_enabled(provider_name) {
      errors.push(store_error(
        store,
        "provider_disabled",
        format!("provider not enabled: {provider_name}"),
      ));
      continue;
    }
    selected.push(store);
  }

  let notes_path = notes_store
    .map(Path::to_path_buf)
    .unwrap_or_else(crate::notes::default_store_path);
  let notes_selected = selected.contains(&"notes");
  let eventkit: Vec<&str> = selected.into_iter().filter(|store| *store != "notes").collect();
  let notes_arguments = json!({ "query": query, "limit": limit });

  let (notes, eventkit_hits) = if notes_selected {
    thread::scope(|scope| {
      let notes = scope.spawn(|| search_notes(&notes_path, &notes_arguments));
      let eventkit_hits = search_eventkit(&eventkit, query, limit, arguments, provider);
      let notes = notes
        .join()
        .unwrap_or_else(|_| Err(store_error("notes", "notes_error", "notes search failed")));
      (Some(notes), eventkit_hits)
    })
  } else {
    (None, search_eventkit(&eventkit, query, limit, arguments, provider))
  };

  let mut hits = Vec::new();
  collect(notes, 0, &mut hits, &mut errors);
  for (offset, outcome) in eventkit_hits.into_iter().enumerate() {
    collect(Some(outcome), (offset + 1) as u8, &mut hits, &mut errors);
  }
  hits.sort_by(|left, right| right.score.cmp(&left.score).then(left.order.cmp(&right.order)));
  hits.truncate(limit);

  let mut object = Map::new();
  if !hits.is_empty() {
    object.insert(
      "items".into(),
      Value::Array(hits.into_iter().map(|hit| hit.item).collect()),
    );
  }
  if !errors.is_empty() {
    object.insert("store_errors".into(), Value::Array(errors));
  }
  Ok(Value::Object(object))
}

struct Hit {
  score: u64,
  order: u8,
  item: Value,
}

fn collect(outcome: Option<Result<Vec<Value>, Value>>, order: u8, hits: &mut Vec<Hit>, errors: &mut Vec<Value>) {
  match outcome {
    Some(Ok(items)) => {
      for item in items {
        hits.push(Hit {
          score: item.get("score").and_then(Value::as_u64).unwrap_or(0),
          order,
          item,
        });
      }
    }
    Some(Err(error)) => errors.push(error),
    None => {}
  }
}

fn requested_stores(arguments: &Value) -> Result<(Vec<&'static str>, bool), String> {
  let Some(value) = arguments.get("stores") else {
    return Ok((STORES.to_vec(), false));
  };
  let Some(items) = value.as_array() else {
    return Err("stores must be an array of notes, reminders, or events".into());
  };
  if items.is_empty() {
    return Err("stores must list notes, reminders, or events".into());
  }
  let mut selected = Vec::new();
  for item in items {
    let Some(name) = item.as_str() else {
      return Err("stores must be an array of notes, reminders, or events".into());
    };
    let Some(store) = STORES.into_iter().find(|store| *store == name) else {
      return Err(format!("stores entry '{name}' must be notes, reminders, or events"));
    };
    if !selected.contains(&store) {
      selected.push(store);
    }
  }
  Ok((selected, true))
}

fn store_capability(store: &str) -> &'static str {
  match store {
    "notes" => capabilities::NOTES_SEARCH,
    "reminders" => capabilities::EVENTKIT_REMINDERS_SEARCH,
    "events" => capabilities::EVENTKIT_EVENTS_SEARCH,
    _ => "abridge.search",
  }
}

fn store_provider(store: &str) -> &'static str {
  if store == "notes" { "notes" } else { "eventkit" }
}

fn search_notes(path: &Path, arguments: &Value) -> Result<Vec<Value>, Value> {
  match crate::notes::call_with_store(path, "search_notes", arguments) {
    Ok(Value::Array(items)) => Ok(items.iter().filter_map(|item| compact("notes", item)).collect()),
    Ok(_) => Err(store_error(
      "notes",
      "notes_error",
      "notes search did not return a list",
    )),
    Err(error) => Err(store_error("notes", error.code, error.message)),
  }
}

fn search_eventkit(
  stores: &[&str],
  query: &str,
  limit: usize,
  arguments: &Value,
  provider: &dyn ProviderBridge,
) -> Vec<Result<Vec<Value>, Value>> {
  stores
    .iter()
    .map(|store| search_provider_store(store, query, limit, arguments, provider))
    .collect()
}

fn search_provider_store(
  store: &str,
  query: &str,
  limit: usize,
  arguments: &Value,
  provider: &dyn ProviderBridge,
) -> Result<Vec<Value>, Value> {
  let tool_name = if store == "events" {
    TOOL_SEARCH_EVENTS
  } else {
    TOOL_SEARCH_REMINDERS
  };
  let Some(tool) = tools::resolve_tool(tool_name) else {
    return Err(store_error(store, "provider_error", "search tool is not registered"));
  };
  let mut payload = Map::new();
  payload.insert("query".into(), Value::String(query.to_string()));
  payload.insert("limit".into(), Value::from(limit));
  if store == "events" {
    if let Some(start) = arguments.get("start_date") {
      payload.insert("start_date".into(), start.clone());
    }
    if let Some(end) = arguments.get("end_date") {
      payload.insert("end_date".into(), end.clone());
    }
  }
  let prepared = agent_shape::prepare(tool, &Value::Object(payload));
  let response = provider.call_provider(ProviderRequest {
    provider: "eventkit".into(),
    operation: prepared.operation.clone(),
    payload_json: prepared.payload_json.clone(),
  });
  if !response.ok {
    return Err(provider_failure(store, response.error_json.as_deref()));
  }
  let shaped = agent_shape::shape(tool.name, &prepared, &response.payload_json);
  let value = serde_json::from_str::<Value>(&shaped.text)
    .map_err(|_| store_error(store, "provider_error", "search returned invalid JSON"))?;
  let Some(items) = value.as_array() else {
    return Err(store_error(store, "provider_error", "search did not return a list"));
  };
  Ok(items.iter().filter_map(|item| compact(store, item)).collect())
}

fn provider_failure(store: &str, error_json: Option<&str>) -> Value {
  let parsed = error_json.and_then(|text| serde_json::from_str::<Value>(text).ok());
  let code = parsed
    .as_ref()
    .and_then(|value| value.get("code"))
    .and_then(Value::as_str)
    .unwrap_or("provider_error");
  let message = parsed
    .as_ref()
    .and_then(|value| value.get("message"))
    .and_then(Value::as_str)
    .unwrap_or("provider call failed");
  store_error(store, code, message)
}

fn compact(store: &str, item: &Value) -> Option<Value> {
  let mut object = Map::new();
  object.insert("store".into(), Value::String(store.to_string()));
  match store {
    "notes" => {
      object.insert(
        "note_identifier".into(),
        Value::String(text(item, "identifier")?.to_string()),
      );
      copy_text(&mut object, item, "title");
      if let Some(path) = item.get("folder").and_then(|folder| text(folder, "path")) {
        object.insert("folder_path".into(), Value::String(path.to_string()));
      }
    }
    "reminders" => {
      object.insert(
        "calendar_item_identifier".into(),
        Value::String(text(item, "calendar_item_identifier")?.to_string()),
      );
      copy_text(&mut object, item, "title");
      if let Some(title) = item.get("calendar").and_then(|calendar| text(calendar, "title")) {
        object.insert("list_title".into(), Value::String(title.to_string()));
      }
    }
    "events" => {
      object.insert(
        "event_identifier".into(),
        Value::String(text(item, "event_identifier")?.to_string()),
      );
      copy_text(&mut object, item, "title");
      copy_text(&mut object, item, "start_date");
      if item.get("is_all_day").and_then(Value::as_bool) == Some(true) {
        object.insert("is_all_day".into(), Value::Bool(true));
      }
      if let Some(title) = item.get("calendar").and_then(|calendar| text(calendar, "title")) {
        object.insert("calendar".into(), Value::String(title.to_string()));
      }
    }
    _ => return None,
  }
  if let Some(score) = item.get("score").and_then(Value::as_u64) {
    object.insert("score".into(), Value::from(score));
  }
  if let Some(excerpt) = item
    .get("matches")
    .and_then(Value::as_array)
    .and_then(|matches| matches.first())
    .and_then(|matched| text(matched, "excerpt"))
  {
    object.insert("excerpt".into(), Value::String(excerpt.to_string()));
  }
  Some(Value::Object(object))
}

fn text<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
  value.get(key).and_then(Value::as_str).filter(|text| !text.is_empty())
}

fn copy_text(object: &mut Map<String, Value>, source: &Value, key: &str) {
  if let Some(text) = text(source, key) {
    object.insert(key.to_string(), Value::String(text.to_string()));
  }
}

fn store_error(store: &str, code: impl Into<String>, message: impl Into<String>) -> Value {
  json!({
    "store": store,
    "code": code.into(),
    "message": message.into(),
  })
}

#[cfg(test)]
mod tests {
  use super::search;
  use crate::config::{ProviderRequest, ProviderResponse};
  use crate::providers::ProviderBridge;
  use serde_json::{Value, json};
  use std::sync::Mutex;

  struct Scripted {
    reminders: Mutex<ProviderResponse>,
    events: Mutex<ProviderResponse>,
    calls: Mutex<Vec<ProviderRequest>>,
  }

  impl Scripted {
    fn ok(reminders: Value, events: Value) -> Self {
      Self {
        reminders: Mutex::new(ok_payload(reminders)),
        events: Mutex::new(ok_payload(events)),
        calls: Mutex::new(Vec::new()),
      }
    }

    fn calls(&self) -> Vec<String> {
      self
        .calls
        .lock()
        .expect("calls")
        .iter()
        .map(|request| request.operation.clone())
        .collect()
    }
  }

  fn ok_payload(value: Value) -> ProviderResponse {
    ProviderResponse {
      ok: true,
      payload_json: value.to_string(),
      error_json: None,
    }
  }

  impl ProviderBridge for Scripted {
    fn call_provider(&self, request: ProviderRequest) -> ProviderResponse {
      let response = match request.operation.as_str() {
        "search_reminders" => self.reminders.lock().expect("reminders").clone(),
        "search_events" => self.events.lock().expect("events").clone(),
        _ => ProviderResponse {
          ok: false,
          payload_json: "{}".into(),
          error_json: Some(r#"{"code":"unknown_operation","message":"unexpected operation"}"#.into()),
        },
      };
      self.calls.lock().expect("calls").push(request);
      response
    }
  }

  fn enabled_all() -> Vec<String> {
    vec![
      "notes.search".into(),
      "eventkit.reminders.search".into(),
      "eventkit.events.search".into(),
    ]
  }

  fn providers_on(name: &str) -> bool {
    name == "notes" || name == "eventkit"
  }

  fn reminder(title: &str) -> Value {
    json!({
      "calendar_item_identifier": "rem-1",
      "title": title,
      "calendar": { "calendar_identifier": "list-1", "title": "Errands" }
    })
  }

  fn event(title: &str, notes: &str) -> Value {
    json!({
      "event_identifier": "evt-1",
      "title": title,
      "notes": notes,
      "time_zone": "America/New_York",
      "start_date": "2026-10-20T15:00:00Z",
      "calendar": { "calendar_identifier": "cal-1", "title": "Work" }
    })
  }

  fn items(value: &Value) -> &Vec<Value> {
    value["items"].as_array().expect("items")
  }

  #[test]
  fn ranks_a_title_hit_above_a_weaker_field_in_another_store() {
    let (_db, path) = crate::notes::test_sample_store();
    let provider = Scripted::ok(
      json!([reminder("Alpha Unique")]),
      json!([event("Standup", "alpha unique later")]),
    );
    let found = search(
      &json!({ "query": "alpha unique" }),
      &enabled_all(),
      providers_on,
      &provider,
      Some(&path),
    )
    .expect("search");
    let stores: Vec<_> = items(&found)
      .iter()
      .map(|item| item["store"].as_str().unwrap())
      .collect();
    assert_eq!(stores, vec!["reminders", "events", "notes"]);
    assert!(found["items"][0]["score"].as_u64().unwrap() > found["items"][1]["score"].as_u64().unwrap());
    assert!(found["items"][1]["score"].as_u64().unwrap() > found["items"][2]["score"].as_u64().unwrap());
    assert_eq!(found["items"][0]["calendar_item_identifier"], "rem-1");
    assert_eq!(found["items"][0]["list_title"], "Errands");
    assert_eq!(found["items"][1]["event_identifier"], "evt-1");
    assert_eq!(found["items"][1]["start_date"], "2026-10-20T11:00:00-04:00");
    assert!(found["items"][1].get("is_all_day").is_none());
    assert_eq!(found["items"][1]["calendar"], "Work");
    assert_eq!(found["items"][2]["note_identifier"], "note-h");
    assert_eq!(found["items"][2]["folder_path"], "Notes");
    assert!(found["items"][2]["excerpt"].as_str().unwrap().contains('«'));
    assert!(found.get("store_errors").is_none());
  }

  #[test]
  fn event_start_matches_event_shaping() {
    let provider = Scripted::ok(
      json!([]),
      json!([
        {
          "event_identifier": "evt-day",
          "title": "Alpha Unique",
          "time_zone": "America/New_York",
          "is_all_day": true,
          "start_date": "2026-10-19T04:00:00Z",
          "calendar": { "title": "Work" }
        },
        {
          "event_identifier": "evt-local",
          "title": "Alpha Unique",
          "start_date": "2026-10-20T15:00:00Z",
          "calendar": { "title": "Home" }
        }
      ]),
    );
    let found = search(
      &json!({ "query": "alpha unique", "stores": ["events"], "limit": 10 }),
      &["eventkit.events.search".into()],
      providers_on,
      &provider,
      None,
    )
    .expect("search");
    let day = items(&found)
      .iter()
      .find(|item| item["event_identifier"] == "evt-day")
      .expect("all-day");
    let local = items(&found)
      .iter()
      .find(|item| item["event_identifier"] == "evt-local")
      .expect("local");
    assert_eq!(day["start_date"], "2026-10-19");
    assert_eq!(day["is_all_day"], true);
    let tool = crate::tools::resolve_tool(crate::tools::TOOL_SEARCH_EVENTS).expect("tool");
    let prepared = crate::agent_shape::prepare(tool, &json!({ "query": "alpha unique", "limit": 10 }));
    let shaped = crate::agent_shape::shape(
      tool.name,
      &prepared,
      &json!([{
        "event_identifier": "evt-local",
        "title": "Alpha Unique",
        "start_date": "2026-10-20T15:00:00Z"
      }])
      .to_string(),
    );
    let shaped: serde_json::Value = serde_json::from_str(&shaped.text).expect("json");
    assert_eq!(local["start_date"], shaped[0]["start_date"]);
    assert!(local.get("is_all_day").is_none());
  }

  #[test]
  fn store_filter_skips_the_other_stores() {
    let (_db, path) = crate::notes::test_sample_store();
    let provider = Scripted::ok(json!([reminder("Alpha Unique")]), json!([event("Alpha Unique", "")]));
    let found = search(
      &json!({ "query": "alpha unique", "stores": ["notes"] }),
      &enabled_all(),
      providers_on,
      &provider,
      Some(&path),
    )
    .expect("search");
    assert_eq!(items(&found).len(), 1);
    assert_eq!(found["items"][0]["store"], "notes");
    assert!(provider.calls().is_empty());
  }

  #[test]
  fn searches_only_the_enabled_store() {
    let (_db, path) = crate::notes::test_sample_store();
    let provider = Scripted::ok(json!([reminder("Alpha Unique")]), json!([event("Alpha Unique", "")]));
    let found = search(
      &json!({ "query": "alpha unique" }),
      &["eventkit.events.search".into()],
      providers_on,
      &provider,
      Some(&path),
    )
    .expect("search");
    assert_eq!(items(&found).len(), 1);
    assert_eq!(found["items"][0]["store"], "events");
    assert_eq!(provider.calls(), vec!["search_events".to_string()]);
    assert!(found.get("store_errors").is_none());
  }

  #[test]
  fn a_denied_store_does_not_drop_the_others() {
    let (_db, path) = crate::notes::test_sample_store();
    let provider = Scripted {
      reminders: Mutex::new(ProviderResponse {
        ok: false,
        payload_json: "{}".into(),
        error_json: Some(r#"{"code":"permission_denied","message":"Reminders access not granted"}"#.into()),
      }),
      events: Mutex::new(ok_payload(json!([event("Alpha Unique", "")]))),
      calls: Mutex::new(Vec::new()),
    };
    let found = search(
      &json!({ "query": "alpha unique" }),
      &enabled_all(),
      providers_on,
      &provider,
      Some(&path),
    )
    .expect("partial success");
    let stores: Vec<_> = items(&found)
      .iter()
      .map(|item| item["store"].as_str().unwrap())
      .collect();
    assert!(stores.contains(&"notes"));
    assert!(stores.contains(&"events"));
    assert!(!stores.contains(&"reminders"));
    assert_eq!(found["store_errors"][0]["store"], "reminders");
    assert_eq!(found["store_errors"][0]["code"], "permission_denied");
  }

  #[test]
  fn a_missing_notes_store_leaves_the_other_hits() {
    let provider = Scripted::ok(json!([]), json!([event("Alpha Unique", "")]));
    let missing = std::env::temp_dir().join("abridge-cross-search-missing-note-store.sqlite");
    let found = search(
      &json!({ "query": "alpha unique" }),
      &enabled_all(),
      providers_on,
      &provider,
      Some(&missing),
    )
    .expect("partial success");
    assert_eq!(found["items"][0]["store"], "events");
    assert_eq!(found["store_errors"][0]["store"], "notes");
    assert_eq!(found["store_errors"][0]["code"], "notes_store_not_found");
  }

  #[test]
  fn an_explicit_disabled_store_is_an_error_not_a_silent_skip() {
    let provider = Scripted::ok(json!([]), json!([]));
    let found = search(
      &json!({ "query": "alpha", "stores": ["notes", "events"] }),
      &["eventkit.events.search".into()],
      providers_on,
      &provider,
      None,
    )
    .expect("search");
    assert_eq!(found["store_errors"][0]["store"], "notes");
    assert_eq!(found["store_errors"][0]["code"], "capability_disabled");
    assert_eq!(provider.calls(), vec!["search_events".to_string()]);
  }

  #[test]
  fn event_window_matches_search_events_when_dates_are_omitted() {
    let provider = Scripted::ok(json!([]), json!([]));
    let arguments = json!({ "query": "alpha", "stores": ["events"] });
    search(
      &arguments,
      &["eventkit.events.search".into()],
      providers_on,
      &provider,
      None,
    )
    .expect("search");
    let tool = crate::tools::resolve_tool(crate::tools::TOOL_SEARCH_EVENTS).expect("tool");
    let prepared = crate::agent_shape::prepare(tool, &json!({ "query": "alpha", "limit": 20 }));
    let recorded = provider.calls.lock().expect("calls");
    assert_eq!(recorded[0].operation, "search_events");
    assert_eq!(recorded[0].payload_json, prepared.payload_json);
  }

  #[test]
  fn rejects_an_empty_store_filter() {
    let provider = Scripted::ok(json!([]), json!([]));
    let err = search(
      &json!({ "query": "alpha", "stores": [] }),
      &enabled_all(),
      providers_on,
      &provider,
      None,
    )
    .expect_err("empty stores");
    assert!(err.contains("stores"), "{err}");
    assert!(provider.calls().is_empty());
  }
}

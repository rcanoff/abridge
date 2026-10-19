//! In-memory search index for the Notes store.
//!
//! The index is rebuilt when `NoteStore.sqlite` or its `-wal` sibling changes size or mtime.
//! Repeat searches reuse the decoded text.

use prost::Message;
use serde_json::{Value, json};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, LazyLock, Mutex, MutexGuard};
use std::time::SystemTime;

use super::attachment_file;
use super::decode;
use super::error::NotesError;
use super::markdown;
use super::proto_note::{AttributeRun, NoteDocument};
use super::query;
use super::shape;
use super::store::{self, EntityRow, Snapshot, SqlValue};
use crate::fuzzy::{self, Field};

const TITLE_WEIGHT: u32 = 8;
const FOLDER_WEIGHT: u32 = 2;
const BODY_WEIGHT: u32 = 1;
const ATTACHMENT_WEIGHT: u32 = 3;
const MAX_MATCHES: usize = 3;
const DEFAULT_LIMIT: u64 = 20;
const MAX_LIMIT: u64 = 100;
/// Seconds between the Unix epoch and the Core Data epoch (2001-01-01T00:00:00Z).
const CORE_DATA_EPOCH_OFFSET: f64 = 978_307_200.0;

struct OwnedField {
  label: String,
  text: String,
  weight: u32,
  per_line: bool,
  attachment_identifier: Option<String>,
  attachment_title: Option<String>,
}

struct NoteDoc {
  index: usize,
  fields: Vec<OwnedField>,
}

struct Index {
  snap: Snapshot,
  notes: Vec<NoteDoc>,
}

#[derive(Clone, PartialEq, Eq)]
struct FileStamp {
  len: u64,
  modified: SystemTime,
}

#[derive(Clone, PartialEq, Eq)]
struct StoreStamp {
  db: FileStamp,
  wal: Option<FileStamp>,
}

struct Entry {
  stamp: StoreStamp,
  index: Arc<Index>,
  generation: u64,
}

static CACHE: LazyLock<Mutex<HashMap<PathBuf, Entry>>> = LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_GENERATION: AtomicU64 = AtomicU64::new(1);

#[cfg(test)]
thread_local! {
  static BEFORE_PUBLISH: std::cell::Cell<Option<fn(&Path)>> = std::cell::Cell::new(None);
}

pub(crate) fn search_notes(path: &Path, arguments: &Value) -> Result<Value, NotesError> {
  super::resolve::check_folder_choice(arguments, false)?;
  let query_text = query::required_identifier(arguments, "query")?;
  let modified_after = optional_bound(arguments, "modified_after")?;
  let modified_before = optional_bound(arguments, "modified_before")?;
  let (limit, offset) = limit_offset(arguments)?;
  let index = cached_index(path)?;
  let folder_identifier = super::resolve::folder_identifier(&index.snap, arguments)?;
  let folder_pk = folder_pk(&index.snap, folder_identifier.as_deref());
  let selected: Vec<&NoteDoc> = index
    .notes
    .iter()
    .filter(|note| included(&index.snap, note.index, folder_pk, modified_after, modified_before))
    .collect();
  let docs: Vec<Vec<Field<'_>>> = selected
    .iter()
    .map(|note| note.fields.iter().map(borrow_field).collect())
    .collect();
  let hits = fuzzy::search(&docs, &query_text, offset, limit);
  let payload = hits
    .iter()
    .map(|hit| hit_json(&index.snap, selected[hit.index], hit))
    .collect();
  Ok(Value::Array(payload))
}

fn borrow_field(field: &OwnedField) -> Field<'_> {
  Field {
    label: std::borrow::Cow::Borrowed(&field.label),
    text: &field.text,
    weight: field.weight,
    per_line: field.per_line,
  }
}

fn hit_json(snap: &Snapshot, note: &NoteDoc, hit: &fuzzy::Hit) -> Value {
  let row = &snap.notes[note.index];
  let mut object = shape::note_summary(snap, row);
  object.remove("snippet");
  object.insert("score".into(), json!(hit.score));
  if !hit.matches.is_empty() {
    let matches = hit
      .matches
      .iter()
      .take(MAX_MATCHES)
      .map(|matched| {
        let mut value = json!({ "field": matched.field, "excerpt": matched.excerpt });
        if let Some(field) = note.fields.iter().find(|field| field.label == matched.field) {
          if let Some(identifier) = &field.attachment_identifier {
            value["attachment_identifier"] = json!(identifier);
          }
          if let Some(title) = &field.attachment_title {
            value["attachment_title"] = json!(title);
          }
        }
        value
      })
      .collect();
    object.insert("matches".into(), Value::Array(matches));
  }
  Value::Object(object)
}

/// `None` means no folder filter. `Some(None)` means the folder identifier is unknown.
fn folder_pk(snap: &Snapshot, identifier: Option<&str>) -> Option<Option<i64>> {
  let identifier = identifier?;
  Some(store::row_by_identifier(&snap.folders, identifier).map(|row| row.pk))
}

fn included(
  snap: &Snapshot,
  index: usize,
  folder_pk: Option<Option<i64>>,
  modified_after: Option<f64>,
  modified_before: Option<f64>,
) -> bool {
  let note = &snap.notes[index];
  // Same rule as notes_list_notes: a named folder searches that folder, including Recently Deleted.
  if folder_pk.is_none() && !query::in_note_list(snap, note) {
    return false;
  }
  if let Some(folder) = folder_pk {
    let Some(pk) = folder else {
      return false;
    };
    if store::foreign_key(note, "folder") != Some(pk) {
      return false;
    }
  }
  if modified_after.is_some() || modified_before.is_some() {
    let Some(modified) = modification_unix(note) else {
      return false;
    };
    if modified_after.is_some_and(|bound| modified <= bound) {
      return false;
    }
    if modified_before.is_some_and(|bound| modified >= bound) {
      return false;
    }
  }
  true
}

fn modification_unix(note: &EntityRow) -> Option<f64> {
  let seconds = match store::non_null(note, "modificationDate") {
    Some(SqlValue::Real(value)) => *value,
    Some(SqlValue::Int(value)) => *value as f64,
    _ => return None,
  };
  Some(seconds + CORE_DATA_EPOCH_OFFSET)
}

fn cached_index(path: &Path) -> Result<Arc<Index>, NotesError> {
  let generation = NEXT_GENERATION.fetch_add(1, Ordering::SeqCst);
  let before = store_stamp(path);
  if let Some(stamp) = &before {
    let guard = lock();
    if let Some(entry) = guard.get(path)
      && &entry.stamp == stamp
    {
      return Ok(Arc::clone(&entry.index));
    }
  }
  let snap = store::load(path)?;
  let notes = index_notes(path, &snap);
  #[cfg(test)]
  run_index_hook(path);
  let after = store_stamp(path);
  let index = Arc::new(Index { snap, notes });
  // Publish only when the store did not move while this index was built, and never let an
  // older builder replace an entry a newer builder already published.
  if let Some(stamp) = before.filter(|stamp| after.as_ref() == Some(stamp)) {
    let mut guard = lock();
    let newer = guard.get(path).is_some_and(|entry| entry.generation > generation);
    if !newer {
      guard.retain(|cached, _| cached.as_path() == path || cached.exists());
      guard.insert(
        path.to_path_buf(),
        Entry {
          stamp,
          index: Arc::clone(&index),
          generation,
        },
      );
    }
  }
  Ok(index)
}

#[cfg(test)]
fn run_index_hook(path: &Path) {
  if let Some(hook) = BEFORE_PUBLISH.with(std::cell::Cell::take) {
    hook(path);
  }
}

/// Runs once, after the index is built and before it is published. The hook may publish a newer
/// entry or change the store; this builder then keeps the newer entry and skips a stale stamp.
#[cfg(test)]
pub(crate) fn set_index_hook(hook: Option<fn(&Path)>) {
  BEFORE_PUBLISH.with(|cell| cell.set(hook));
}

#[cfg(test)]
pub(crate) fn cached_generation(path: &Path) -> Option<u64> {
  lock().get(path).map(|entry| entry.generation)
}

#[cfg(test)]
fn seed_newer_index(path: &Path) {
  let Some(stamp) = store_stamp(path) else {
    return;
  };
  let Ok(snap) = store::load(path) else {
    return;
  };
  let mut guard = lock();
  guard.insert(
    path.to_path_buf(),
    Entry {
      stamp,
      index: Arc::new(Index {
        snap,
        notes: Vec::new(),
      }),
      generation: u64::MAX,
    },
  );
}

fn lock() -> MutexGuard<'static, HashMap<PathBuf, Entry>> {
  CACHE.lock().unwrap_or_else(|err| err.into_inner())
}

fn store_stamp(path: &Path) -> Option<StoreStamp> {
  Some(StoreStamp {
    db: file_stamp(path)?,
    wal: file_stamp(&sibling(path, "-wal")),
  })
}

fn sibling(path: &Path, suffix: &str) -> PathBuf {
  let mut name = path.file_name().unwrap_or_default().to_os_string();
  name.push(suffix);
  path.with_file_name(name)
}

fn file_stamp(path: &Path) -> Option<FileStamp> {
  let meta = std::fs::metadata(path).ok()?;
  if !meta.is_file() {
    return None;
  }
  Some(FileStamp {
    len: meta.len(),
    modified: meta.modified().ok()?,
  })
}

fn index_notes(path: &Path, snap: &Snapshot) -> Vec<NoteDoc> {
  snap
    .notes
    .iter()
    .enumerate()
    .map(|(index, note)| NoteDoc {
      index,
      fields: note_fields(path, snap, note),
    })
    .collect()
}

fn note_fields(path: &Path, snap: &Snapshot, note: &EntityRow) -> Vec<OwnedField> {
  let mut fields = Vec::new();
  push_field(
    &mut fields,
    "title",
    store::text(note, "title").unwrap_or(""),
    TITLE_WEIGHT,
    false,
  );
  if let Some(folder) = shape::folder_of(snap, note) {
    push_field(
      &mut fields,
      "folder",
      &shape::folder_path(snap, folder),
      FOLDER_WEIGHT,
      false,
    );
  }
  let names = replacement_names(snap, note.pk);
  let mut body = body_text(snap, note, &names);
  append_table_rows(snap, note, &mut body);
  push_field(&mut fields, "body", &body, BODY_WEIGHT, true);
  for attachment in shape::visible_attachments(snap, note) {
    let text = attachment_text(path, snap, attachment);
    if text.is_empty() {
      continue;
    }
    let attachment_identifier = store::text(attachment, "identifier")
      .filter(|identifier| !identifier.is_empty())
      .map(str::to_string);
    let attachment_title = store::text(attachment, "title")
      .filter(|title| !title.is_empty())
      .or_else(|| media_filename(snap, attachment))
      .filter(|title| !title.is_empty())
      .map(str::to_string);
    fields.push(OwnedField {
      label: attachment_label(snap, attachment),
      text,
      weight: ATTACHMENT_WEIGHT,
      per_line: true,
      attachment_identifier,
      attachment_title,
    });
  }
  fields
}

fn push_field(fields: &mut Vec<OwnedField>, label: &str, text: &str, weight: u32, per_line: bool) {
  if text.is_empty() {
    return;
  }
  fields.push(OwnedField {
    label: label.to_string(),
    text: text.to_string(),
    weight,
    per_line,
    attachment_identifier: None,
    attachment_title: None,
  });
}

fn replacement_names(snap: &Snapshot, note_pk: i64) -> HashMap<String, String> {
  let mut names = HashMap::new();
  for row in snap
    .attachments
    .iter()
    .filter(|row| store::foreign_key(row, "note") == Some(note_pk))
  {
    let Some(identifier) = store::text(row, "identifier") else {
      continue;
    };
    let Some(title) = store::text(row, "title").filter(|text| !text.is_empty()) else {
      continue;
    };
    names.insert(identifier.to_string(), title.to_string());
  }
  for row in snap
    .inline_attachments
    .iter()
    .filter(|row| store::foreign_key(row, "note") == Some(note_pk))
  {
    let Some(identifier) = store::text(row, "identifier") else {
      continue;
    };
    let Some(alt) = store::text(row, "altText").filter(|text| !text.is_empty()) else {
      continue;
    };
    names.insert(identifier.to_string(), alt.to_string());
  }
  names
}

fn body_text(snap: &Snapshot, note: &EntityRow, names: &HashMap<String, String>) -> String {
  let mut used = Vec::new();
  let mut text = String::new();
  if let Some(blob) = note_blob(snap, note)
    && let Some((string, runs)) = decode_topotext(blob)
  {
    text = substitute(&string, &runs, names, &mut used);
  }
  for row in snap
    .inline_attachments
    .iter()
    .filter(|row| store::foreign_key(row, "note") == Some(note.pk))
  {
    let Some(alt) = store::text(row, "altText").filter(|text| !text.is_empty()) else {
      continue;
    };
    if store::text(row, "identifier").is_some_and(|identifier| used.iter().any(|used| used == identifier)) {
      continue;
    }
    if !text.is_empty() && !text.ends_with('\n') {
      text.push('\n');
    }
    text.push_str(alt);
  }
  text
}

fn note_blob<'a>(snap: &'a Snapshot, note: &EntityRow) -> Option<&'a [u8]> {
  let pk = store::foreign_key(note, "noteData")?;
  let row = snap.note_data.iter().find(|row| row.pk == pk)?;
  if row.encrypted {
    return None;
  }
  row.data.as_deref()
}

fn decode_topotext(blob: &[u8]) -> Option<(String, Vec<AttributeRun>)> {
  let raw = decode::inflate(blob)?;
  let document = NoteDocument::decode(raw.as_slice()).ok()?;
  let text = document.version.and_then(|version| version.data)?;
  Some((text.string.unwrap_or_default(), text.attribute_run))
}

/// Attribute-run lengths are UTF-16 code units. Each U+FFFC is replaced with the attachment
/// title or inline alt text named by the run that covers it.
fn substitute(string: &str, runs: &[AttributeRun], names: &HashMap<String, String>, used: &mut Vec<String>) -> String {
  let mut out = String::with_capacity(string.len());
  let mut run_index = 0;
  let mut left = runs.first().and_then(|run| run.length).unwrap_or(0);
  if runs.is_empty() {
    left = i32::MAX;
  }
  skip_empty_runs(runs, &mut run_index, &mut left);
  for character in string.chars() {
    if character == '\u{FFFC}' {
      if let Some(identifier) = attachment_identifier(runs, run_index)
        && let Some(name) = names.get(identifier)
      {
        push_inline(&mut out, name);
        if !used.iter().any(|seen| seen == identifier) {
          used.push(identifier.to_string());
        }
      }
    } else {
      out.push(character);
    }
    left -= i32::from(u16::try_from(character.len_utf16()).unwrap_or(u16::MAX));
    skip_empty_runs(runs, &mut run_index, &mut left);
  }
  out
}

fn skip_empty_runs(runs: &[AttributeRun], run_index: &mut usize, left: &mut i32) {
  while *left <= 0 && *run_index + 1 < runs.len() {
    *run_index += 1;
    *left += runs[*run_index].length.unwrap_or(0);
  }
}

fn attachment_identifier(runs: &[AttributeRun], run_index: usize) -> Option<&str> {
  runs
    .get(run_index)?
    .attachment_info
    .as_ref()?
    .attachment_identifier
    .as_deref()
}

fn push_inline(out: &mut String, text: &str) {
  if text.is_empty() {
    return;
  }
  if !out.is_empty() && !out.ends_with(|character: char| character.is_whitespace()) {
    out.push(' ');
  }
  out.push_str(text);
}

fn append_table_rows(snap: &Snapshot, note: &EntityRow, text: &mut String) {
  let referenced = markdown::referenced_attachment_identifiers(snap, note);
  let mut tables: Vec<&EntityRow> = snap
    .attachments
    .iter()
    .filter(|row| {
      store::foreign_key(row, "note") == Some(note.pk)
        && store::text(row, "typeUTI") == Some("com.apple.notes.table")
        && store::text(row, "identifier").is_some_and(|identifier| referenced.contains(identifier))
    })
    .collect();
  tables.sort_by_key(|row| row.pk);
  for row in tables {
    let Some(markdown) = markdown::table_markdown(row) else {
      continue;
    };
    for line in markdown
      .lines()
      .filter(|line| !line.trim().is_empty() && !is_table_rule(line))
    {
      if !text.is_empty() && !text.ends_with('\n') {
        text.push('\n');
      }
      text.push_str(line.trim());
      text.push('\n');
    }
  }
}

fn is_table_rule(line: &str) -> bool {
  let mut cells = line.trim().trim_matches('|').split('|');
  cells.clone().any(|cell| !cell.trim().is_empty())
    && cells.all(|cell| {
      let cell = cell.trim();
      cell.is_empty() || cell.chars().all(|character| character == '-' || character == ':')
    })
}

fn attachment_label(snap: &Snapshot, row: &EntityRow) -> String {
  let identifier = store::text(row, "identifier").unwrap_or("");
  let name = store::text(row, "title")
    .filter(|text| !text.is_empty())
    .or_else(|| media_filename(snap, row))
    .filter(|text| !text.is_empty());
  match name {
    Some(name) if !identifier.is_empty() => format!("attachment: {identifier} {name}"),
    Some(name) => format!("attachment: {name}"),
    None if !identifier.is_empty() => format!("attachment: {identifier}"),
    None => "attachment".to_string(),
  }
}

fn media_filename<'a>(snap: &'a Snapshot, row: &EntityRow) -> Option<&'a str> {
  let media = store::row_by_pk(&snap.media, store::foreign_key(row, "media")?)?;
  store::text(media, "filename")
}

fn attachment_text(path: &Path, snap: &Snapshot, row: &EntityRow) -> String {
  let mut lines = Vec::new();
  for attribute in ["title", "summary", "ocrSummary", "handwritingSummary", "urlString"] {
    if let Some(text) = store::text(row, attribute).filter(|text| !text.is_empty()) {
      lines.push(text.to_string());
    }
  }
  if let Some(media) = store::foreign_key(row, "media").and_then(|pk| store::row_by_pk(&snap.media, pk))
    && let Some(filename) = store::text(media, "filename").filter(|text| !text.is_empty())
  {
    lines.push(filename.to_string());
  }
  let mut text = lines.join("\n");
  let seen: HashSet<String> = text.lines().map(str::to_string).collect();
  append_new_lines(
    &mut text,
    &attachment_file::indexed_document_text(path, snap, row),
    &seen,
  );
  text
}

fn append_new_lines(text: &mut String, extra: &str, seen: &HashSet<String>) {
  for line in extra.lines() {
    let line = line.trim();
    if line.is_empty() || seen.contains(line) {
      continue;
    }
    if !text.is_empty() && !text.ends_with('\n') {
      text.push('\n');
    }
    text.push_str(line);
  }
}

fn optional_bound(arguments: &Value, key: &str) -> Result<Option<f64>, NotesError> {
  let Some(text) = query::optional_identifier(arguments, key)? else {
    return Ok(None);
  };
  unix_seconds(&text)
    .map(Some)
    .ok_or_else(|| NotesError::new("notes_error", format!("invalid {key}")))
}

fn limit_offset(arguments: &Value) -> Result<(usize, usize), NotesError> {
  let limit = match arguments.get("limit") {
    None | Some(Value::Null) => DEFAULT_LIMIT,
    Some(value) => bounded(value, 1, MAX_LIMIT, "limit")?,
  };
  let offset = match arguments.get("offset") {
    None | Some(Value::Null) => 0,
    Some(value) => bounded(value, 0, u64::MAX, "offset")?,
  };
  Ok((limit as usize, usize::try_from(offset).unwrap_or(usize::MAX)))
}

fn bounded(value: &Value, minimum: u64, maximum: u64, key: &str) -> Result<u64, NotesError> {
  let Some(number) = value.as_u64() else {
    return Err(NotesError::new("notes_error", format!("invalid {key}")));
  };
  if number < minimum || number > maximum {
    return Err(NotesError::new("notes_error", format!("invalid {key}")));
  }
  Ok(number)
}

fn unix_seconds(text: &str) -> Option<f64> {
  crate::datetime::rfc3339_unix_seconds(text)
}

#[cfg(test)]
pub(crate) fn cached_index_ptr(path: &Path) -> Option<usize> {
  lock().get(path).map(|entry| Arc::as_ptr(&entry.index) as usize)
}

#[cfg(test)]
mod tests {
  use super::super::attachment_fixture::attachment_store;
  use super::super::call_with_store;
  use super::super::fixture::{add_recently_deleted, sample_store};
  use super::{cached_index_ptr, unix_seconds};
  use serde_json::json;
  use std::time::{Duration, SystemTime};

  fn search(path: &std::path::Path, arguments: serde_json::Value) -> serde_json::Value {
    call_with_store(path, "search_notes", &arguments).unwrap()
  }

  #[test]
  fn parses_rfc3339_bounds() {
    assert_eq!(unix_seconds("1970-01-01T00:00:00Z"), Some(0.0));
    assert_eq!(unix_seconds("2001-01-01T00:01:40Z"), Some(978_307_200.0 + 100.0));
    assert_eq!(unix_seconds("1970-01-01T01:00:00+01:00"), Some(0.0));
    assert_eq!(unix_seconds("1970-01-01T00:00:00.500Z"), Some(0.5));
    assert!(unix_seconds("not-a-date").is_none());
  }

  #[test]
  fn finds_body_ocr_table_and_filters_folder_and_date() {
    let (_db, path) = sample_store();
    let body = search(&path, json!({ "query": "alpha unique" }));
    assert_eq!(body.as_array().unwrap().len(), 1);
    assert_eq!(body[0]["identifier"], "note-h");
    assert!(body[0].get("snippet").is_none());
    assert!(body[0].get("score").is_some());
    assert!(body[0]["matches"][0]["excerpt"].as_str().unwrap().contains('«'));

    let ocr = search(&path, json!({ "query": "'ocr hit" }));
    assert_eq!(ocr[0]["identifier"], "note-i");
    assert_eq!(ocr[0]["matches"][0]["field"], "attachment: att-1 Beta Unique");
    assert_eq!(ocr[0]["matches"][0]["excerpt"], "«ocr» hit");
    assert_eq!(ocr[0]["matches"][0]["attachment_identifier"], "att-1");
    assert_eq!(ocr[0]["matches"][0]["attachment_title"], "Beta Unique");
    assert!(body[0]["matches"][0].get("attachment_identifier").is_none());
    assert!(body[0]["matches"][0].get("attachment_title").is_none());

    let table = search(&path, json!({ "query": "right" }));
    assert_eq!(table[0]["identifier"], "note-j");
    assert_eq!(table[0]["matches"][0]["field"], "body");
    assert_eq!(table[0]["matches"][0]["excerpt"], "| «Right» | Left |");

    let archived = search(&path, json!({ "query": "alpha", "folder_identifier": "fold-2" }));
    assert!(archived.as_array().unwrap().is_empty());
    let notes = search(&path, json!({ "query": "alpha", "folder_identifier": "fold-1" }));
    assert_eq!(notes[0]["identifier"], "note-h");

    let after = search(
      &path,
      json!({ "query": "alpha", "modified_after": "2001-01-01T00:00:00Z" }),
    );
    assert_eq!(after[0]["identifier"], "note-h");
    let before = search(
      &path,
      json!({ "query": "alpha", "modified_before": "2001-01-01T00:01:40Z" }),
    );
    assert!(before.as_array().unwrap().is_empty());
    let exact = search(
      &path,
      json!({ "query": "alpha", "modified_after": "2001-01-01T00:01:40Z" }),
    );
    assert!(exact.as_array().unwrap().is_empty());

    let invalid = call_with_store(
      &path,
      "search_notes",
      &json!({ "query": "alpha", "modified_after": "tomorrow" }),
    )
    .unwrap_err();
    assert_eq!(invalid.code, "notes_error");
  }

  #[test]
  fn finds_a_tag_from_inline_alt_text() {
    let (_dir, path) = attachment_store();
    let hits = search(&path, json!({ "query": "'#groceries" }));
    assert_eq!(hits.as_array().unwrap().len(), 1);
    assert_eq!(hits[0]["identifier"], "note-i");
    let excerpt = hits[0]["matches"][0]["excerpt"].as_str().unwrap();
    assert!(excerpt.contains("#groceries") || excerpt.contains("groceries"));
  }

  #[test]
  fn rebuilds_the_cache_when_the_store_changes() {
    let (_db, path) = sample_store();
    let _ = search(&path, json!({ "query": "from suffix" }));
    let first = cached_index_ptr(&path);
    let _ = search(&path, json!({ "query": "from suffix" }));
    assert_eq!(cached_index_ptr(&path), first);

    let conn = rusqlite::Connection::open(&path).unwrap();
    conn
      .execute(
        "UPDATE ZICCLOUDSYNCINGOBJECT SET ZTITLE1 = 'cache-rebuild-token' WHERE ZIDENTIFIER = 'note-a'",
        [],
      )
      .unwrap();
    drop(conn);
    let file = std::fs::File::options().write(true).open(&path).unwrap();
    file.set_modified(SystemTime::now() + Duration::from_secs(2)).unwrap();

    let hits = search(&path, json!({ "query": "'cache-rebuild-token" }));
    assert_eq!(hits[0]["identifier"], "note-a");
    assert_ne!(cached_index_ptr(&path), first);
    let stale = search(&path, json!({ "query": "'from suffix" }));
    assert!(stale.as_array().unwrap().is_empty());
  }

  #[test]
  fn replaces_an_object_character_with_inline_alt_text() {
    use std::collections::HashMap;

    use crate::notes::proto_note::{AttachmentInfo, AttributeRun};

    let names = HashMap::from([("tag-1".to_string(), "#groceries".to_string())]);
    let runs = vec![AttributeRun {
      length: Some(1),
      attachment_info: Some(AttachmentInfo {
        attachment_identifier: Some("tag-1".into()),
        type_uti: None,
      }),
      ..AttributeRun::default()
    }];
    let mut used = Vec::new();
    let text = super::substitute("\u{FFFC}", &runs, &names, &mut used);
    assert_eq!(text, "#groceries");
    assert_eq!(used, vec!["tag-1".to_string()]);
  }

  #[test]
  fn skips_recently_deleted_unless_that_folder_is_named() {
    let (_db, path) = sample_store();
    add_recently_deleted(&path);
    let open = search(&path, json!({ "query": "'old" }));
    assert!(
      open
        .as_array()
        .unwrap()
        .iter()
        .all(|hit| hit["identifier"] != "note-trashed")
    );
    let trashed = search(&path, json!({ "query": "'old", "folder_identifier": "trash-1" }));
    assert_eq!(trashed[0]["identifier"], "note-trashed");
  }

  fn retitle_during_index(path: &std::path::Path) {
    let conn = rusqlite::Connection::open(path).unwrap();
    conn
      .execute(
        "UPDATE ZICCLOUDSYNCINGOBJECT SET ZTITLE1 = 'fresh-token' WHERE ZIDENTIFIER = 'note-a'",
        [],
      )
      .unwrap();
    drop(conn);
    let file = std::fs::File::options().write(true).open(path).unwrap();
    file.set_modified(SystemTime::now() + Duration::from_secs(5)).unwrap();
  }

  fn publish_newer_during_index(path: &std::path::Path) {
    super::seed_newer_index(path);
  }

  #[test]
  fn a_store_change_during_indexing_is_not_cached_under_the_new_stamp() {
    let (_db, path) = sample_store();
    super::set_index_hook(Some(retitle_during_index));
    let during = search(&path, json!({ "query": "'fresh-token" }));
    assert!(during.as_array().unwrap().is_empty());
    let after = search(&path, json!({ "query": "'fresh-token" }));
    assert_eq!(after[0]["identifier"], "note-a");
    let stale = search(&path, json!({ "query": "'from suffix" }));
    assert!(stale.as_array().unwrap().is_empty());
  }

  #[test]
  fn an_older_builder_does_not_replace_a_newer_index() {
    let (_db, path) = sample_store();
    super::set_index_hook(Some(publish_newer_during_index));
    let built = search(&path, json!({ "query": "'from suffix" }));
    assert_eq!(built[0]["identifier"], "note-a");
    assert_eq!(super::cached_generation(&path), Some(u64::MAX));
    let cached = search(&path, json!({ "query": "'from suffix" }));
    assert!(cached.as_array().unwrap().is_empty());
  }
}

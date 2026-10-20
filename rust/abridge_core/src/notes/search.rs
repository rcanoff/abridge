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
/// Matched line plus at most one line before it and one line after it.
const SURROUNDING_LINES: usize = 1;
const EXCERPT_CAP: usize = 600;
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
    .map(|hit| hit_json(path, &index.snap, selected[hit.index], hit))
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

fn hit_json(path: &Path, snap: &Snapshot, note: &NoteDoc, hit: &fuzzy::Hit) -> Value {
  let row = &snap.notes[note.index];
  let mut object = shape::note_summary(snap, row);
  object.remove("snippet");
  object.insert("score".into(), json!(hit.score));
  let matches = merged_matches(path, snap, note, hit);
  if !matches.is_empty() {
    object.insert("matches".into(), Value::Array(matches));
  }
  let attachments = compact_attachments(path, snap, row);
  if !attachments.is_empty() {
    object.insert("attachments".into(), Value::Array(attachments));
  }
  Value::Object(object)
}

/// One match per attachment, and one per other field. Terms on the same line share an excerpt.
/// Terms on different lines are joined while the result stays within the excerpt cap; otherwise
/// the higher-scoring excerpt is kept. `hit.matches` is already best-first.
fn merged_matches(path: &Path, snap: &Snapshot, note: &NoteDoc, hit: &fuzzy::Hit) -> Vec<Value> {
  let mut groups: Vec<(&OwnedField, Vec<&fuzzy::Match>)> = Vec::new();
  for matched in &hit.matches {
    let Some(field) = note.fields.iter().find(|field| field.label == matched.field) else {
      continue;
    };
    if let Some(group) = groups.iter_mut().find(|(grouped, _)| same_match(grouped, field)) {
      group.1.push(matched);
    } else {
      groups.push((field, vec![matched]));
    }
  }
  groups
    .into_iter()
    .take(MAX_MATCHES)
    .map(|(field, matches)| {
      let excerpts: Vec<&str> = matches.iter().map(|matched| matched.excerpt.as_str()).collect();
      let mut value = json!({
        "field": field.label,
        "excerpt": merged_excerpt(&field.text, &excerpts),
      });
      if let Some(identifier) = &field.attachment_identifier {
        value["attachment_identifier"] = json!(identifier);
        if let Some(row) = snap
          .attachments
          .iter()
          .find(|row| store::text(row, "identifier") == Some(identifier.as_str()))
        {
          value["kind"] = json!(attachment_file::attachment_kind(path, snap, row));
          if let Some(count) = attachment_file::page_count(path, snap, row) {
            value["page_count"] = json!(count);
          }
        }
      }
      if let Some(title) = &field.attachment_title {
        value["attachment_title"] = json!(title);
      }
      value
    })
    .collect()
}

fn same_match(left: &OwnedField, right: &OwnedField) -> bool {
  match (&left.attachment_identifier, &right.attachment_identifier) {
    (Some(left_id), Some(right_id)) => left_id == right_id,
    (None, None) => left.label == right.label,
    _ => false,
  }
}

fn merged_excerpt(text: &str, excerpts: &[&str]) -> String {
  let Some(first) = excerpts.first() else {
    return String::new();
  };
  if excerpts.len() == 1 {
    return context_excerpt(text, first);
  }
  let chars: Vec<char> = text.chars().collect();
  let lines = non_empty_line_spans(&chars);
  let mut placements = Vec::new();
  for excerpt in excerpts {
    let (needle, marks) = split_marks(excerpt);
    let needle_chars: Vec<char> = needle.chars().collect();
    let Some(start) = find_chars(&chars, &needle_chars) else {
      continue;
    };
    let end = start + marks.len();
    let line = lines
      .iter()
      .position(|(line_start, line_end)| start < *line_end && end > *line_start);
    placements.push((start, marks, line));
  }
  if placements.is_empty() {
    return cap_marked(&first.chars().collect::<Vec<_>>());
  }
  let same_line = placements.iter().all(|(_, _, line)| line == &placements[0].2);
  if same_line {
    let (window_start, window_end) = line_window(&chars, &lines, placements[0].2);
    let rendered = render_marks(&chars, &placements, window_start, window_end);
    return cap_marked(&rendered.chars().collect::<Vec<_>>());
  }
  let mut joined = String::new();
  for excerpt in excerpts {
    let piece = context_excerpt(text, excerpt);
    let next = if joined.is_empty() {
      piece
    } else {
      format!("{joined}\n{piece}")
    };
    if next.chars().count() > EXCERPT_CAP {
      break;
    }
    joined = next;
  }
  if joined.is_empty() {
    context_excerpt(text, first)
  } else {
    joined
  }
}

fn line_window(chars: &[char], lines: &[(usize, usize)], line: Option<usize>) -> (usize, usize) {
  let Some(index) = line else {
    return (0, chars.len());
  };
  if lines.is_empty() {
    return (0, chars.len());
  }
  let from = index.saturating_sub(SURROUNDING_LINES);
  let to = (index + SURROUNDING_LINES).min(lines.len() - 1);
  (lines[from].0, lines[to].1)
}

fn render_marks(chars: &[char], placements: &[(usize, Vec<bool>, Option<usize>)], start: usize, end: usize) -> String {
  let mut flags = vec![false; chars.len()];
  for (at, marks, _) in placements {
    for (offset, marked) in marks.iter().enumerate() {
      if *marked && let Some(slot) = flags.get_mut(at + offset) {
        *slot = true;
      }
    }
  }
  let mut out = String::new();
  let mut index = start.min(chars.len());
  let end = end.min(chars.len());
  while index < end {
    if flags[index] {
      out.push('«');
      while index < end && flags[index] {
        out.push(chars[index]);
        index += 1;
      }
      out.push('»');
    } else {
      out.push(chars[index]);
      index += 1;
    }
  }
  out
}

/// Top-level body attachments, in body order, with no saved text. Gallery pages stay off this list.
fn compact_attachments(path: &Path, snap: &Snapshot, note: &EntityRow) -> Vec<Value> {
  let order = markdown::referenced_attachment_order(snap, note);
  let mut cards = Vec::new();
  for identifier in &order {
    let Some(row) = snap
      .attachments
      .iter()
      .find(|row| store::text(row, "identifier") == Some(identifier.as_str()))
    else {
      continue;
    };
    if store::foreign_key(row, "note") != Some(note.pk) {
      continue;
    }
    if store::text(row, "typeUTI") == Some("com.apple.notes.table") && markdown::table_markdown(row).is_some() {
      continue;
    }
    if let Some(parent) = store::foreign_key(row, "parentAttachment")
      && let Some(parent) = store::row_by_pk(&snap.attachments, parent)
      && let Some(parent_id) = store::text(parent, "identifier")
      && order.iter().any(|item| item == parent_id)
    {
      continue;
    }
    let mut card = json!({ "identifier": identifier });
    if let Some(title) = store::text(row, "title").filter(|title| !title.is_empty()) {
      card["title"] = json!(title);
    } else if let Some(title) = media_filename(snap, row).filter(|title| !title.is_empty()) {
      card["title"] = json!(title);
    }
    card["kind"] = json!(attachment_file::attachment_kind(path, snap, row));
    if let Some(count) = attachment_file::page_count(path, snap, row) {
      card["page_count"] = json!(count);
    }
    cards.push(card);
  }
  cards
}

/// The matched line plus up to two surrounding lines (one before and one after), capped at 600
/// characters. `excerpt` is the fuzzy window of that line, with the match already inside `«»`.
fn context_excerpt(text: &str, excerpt: &str) -> String {
  let (needle, marks) = split_marks(excerpt);
  let chars: Vec<char> = text.chars().collect();
  let needle_chars: Vec<char> = needle.chars().collect();
  let Some(start) = find_chars(&chars, &needle_chars) else {
    return cap_marked(&excerpt.chars().collect::<Vec<_>>());
  };
  let end = start + needle_chars.len();
  let lines = non_empty_line_spans(&chars);
  let (window_start, window_end) = if lines.is_empty() {
    (0, chars.len())
  } else {
    let first = lines
      .iter()
      .position(|(line_start, line_end)| start < *line_end && end > *line_start)
      .unwrap_or(0);
    let last = lines
      .iter()
      .rposition(|(line_start, line_end)| start < *line_end && end > *line_start)
      .unwrap_or(first);
    let from = first.saturating_sub(SURROUNDING_LINES);
    let to = (last + SURROUNDING_LINES).min(lines.len() - 1);
    (lines[from].0, lines[to].1)
  };
  let mut out = Vec::new();
  let mut index = window_start;
  while index < window_end {
    let marked = index >= start && index < end && marks.get(index - start).copied().unwrap_or(false);
    if marked {
      out.push('«');
      while index < window_end && index < end && marks.get(index - start).copied().unwrap_or(false) {
        out.push(chars[index]);
        index += 1;
      }
      out.push('»');
    } else {
      out.push(chars[index]);
      index += 1;
    }
  }
  cap_marked(&out)
}

fn split_marks(excerpt: &str) -> (String, Vec<bool>) {
  let mut needle = String::new();
  let mut marks = Vec::new();
  let mut on = false;
  for character in excerpt.chars() {
    match character {
      '«' => on = true,
      '»' => on = false,
      _ => {
        needle.push(character);
        marks.push(on);
      }
    }
  }
  (needle, marks)
}

fn find_chars(haystack: &[char], needle: &[char]) -> Option<usize> {
  if needle.is_empty() || needle.len() > haystack.len() {
    return None;
  }
  haystack.windows(needle.len()).position(|window| window == needle)
}

fn non_empty_line_spans(chars: &[char]) -> Vec<(usize, usize)> {
  let mut spans = Vec::new();
  let mut start = 0;
  let mut index = 0;
  while index <= chars.len() {
    if index == chars.len() || chars[index] == '\n' {
      let mut end = index;
      if end > start && chars[end - 1] == '\r' {
        end -= 1;
      }
      if end > start {
        spans.push((start, end));
      }
      start = index + 1;
    }
    if index == chars.len() {
      break;
    }
    index += 1;
  }
  spans
}

fn cap_marked(chars: &[char]) -> String {
  if chars.len() <= EXCERPT_CAP {
    return chars.iter().collect();
  }
  let Some(open) = chars.iter().position(|character| *character == '«') else {
    return chars.iter().take(EXCERPT_CAP).collect();
  };
  let close = chars.iter().rposition(|character| *character == '»').unwrap_or(open);
  let span = close + 1 - open;
  if span >= EXCERPT_CAP {
    let mut kept = Vec::with_capacity(EXCERPT_CAP);
    kept.push('«');
    let room = EXCERPT_CAP.saturating_sub(2);
    let content_start = open + 1;
    let content_len = close.saturating_sub(content_start);
    let take = room.min(content_len);
    kept.extend_from_slice(&chars[content_start..content_start + take]);
    if kept.len() < EXCERPT_CAP {
      kept.push('»');
    }
    return kept.into_iter().take(EXCERPT_CAP).collect();
  }
  let spare = EXCERPT_CAP - span;
  let mut start = open.saturating_sub(spare / 2);
  let mut end = (close + 1 + (spare - spare / 2)).min(chars.len());
  if end.saturating_sub(start) < EXCERPT_CAP.min(chars.len()) {
    if start == 0 {
      end = (start + EXCERPT_CAP).min(chars.len());
    } else {
      start = end.saturating_sub(EXCERPT_CAP);
    }
  }
  if start > open {
    start = open;
    end = (start + EXCERPT_CAP).min(chars.len());
  }
  if end < close + 1 {
    end = (close + 1).min(chars.len());
    start = end.saturating_sub(EXCERPT_CAP);
  }
  chars[start..end].iter().collect()
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
    assert!(body[0].get("attachments").is_none());

    let ocr = search(&path, json!({ "query": "'ocr hit" }));
    assert_eq!(ocr[0]["identifier"], "note-i");
    assert_eq!(ocr[0]["matches"][0]["field"], "attachment: att-1 Beta Unique");
    assert_eq!(ocr[0]["matches"][0]["excerpt"], "sum\n«ocr» «hit»\nink hit");
    assert_eq!(ocr[0]["matches"].as_array().unwrap().len(), 1);
    assert_eq!(ocr[0]["matches"][0]["attachment_identifier"], "att-1");
    assert_eq!(ocr[0]["matches"][0]["attachment_title"], "Beta Unique");
    assert_eq!(ocr[0]["matches"][0]["kind"], "photo");
    assert!(ocr[0]["matches"][0].get("page_count").is_none());
    assert_eq!(ocr[0]["attachments"].as_array().unwrap().len(), 1);
    assert_eq!(ocr[0]["attachments"][0]["identifier"], "att-1");
    assert_eq!(ocr[0]["attachments"][0]["title"], "Beta Unique");
    assert_eq!(ocr[0]["attachments"][0]["kind"], "photo");
    assert!(ocr[0]["attachments"][0].get("page_count").is_none());
    assert!(ocr[0]["attachments"][0].get("text").is_none());
    assert!(body[0]["matches"][0].get("attachment_identifier").is_none());
    assert!(body[0]["matches"][0].get("attachment_title").is_none());
    assert!(body[0]["matches"][0].get("kind").is_none());
    assert!(body[0]["matches"][0].get("page_count").is_none());

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

  #[test]
  fn excerpt_keeps_two_surrounding_lines_the_mark_and_a_600_character_cap() {
    let text = "one\ntwo\nthree target\nfour\nfive";
    assert_eq!(
      super::context_excerpt(text, "three «target»"),
      "two\nthree «target»\nfour"
    );
    assert_eq!(super::context_excerpt("only\nnext\nthird", "«only»"), "«only»\nnext");
    assert_eq!(super::context_excerpt("first\nprior\nend", "«end»"), "prior\n«end»");

    let long = "x".repeat(500);
    let wide = format!("{long}\nplease pay the deposit\n{long}");
    let capped = super::context_excerpt(&wide, "please pay the «deposit»");
    assert!(capped.chars().count() <= 600, "{}", capped.chars().count());
    assert!(capped.contains("«deposit»"));
    assert!(capped.contains('\n'));
    assert!(!capped.contains(&"x".repeat(400)));

    let (_db, path) = sample_store();
    let line = format!("{}uniquetoken{}", "p".repeat(80), "p".repeat(80));
    let ocr = format!("above the match\n{line}\nbelow the match\nout of the window");
    clear_attachment_text(&path, &ocr);
    let hits = search(&path, json!({ "query": "'uniquetoken" }));
    let excerpt = hits[0]["matches"][0]["excerpt"].as_str().unwrap();
    assert!(excerpt.starts_with("above the match\n"));
    assert!(excerpt.contains("«uniquetoken»"));
    assert!(excerpt.contains(&"p".repeat(80)));
    assert!(excerpt.ends_with("\nbelow the match"));
    assert!(!excerpt.contains("out of the window"));
    assert!(excerpt.chars().count() > 120);
    assert!(excerpt.contains('«') && excerpt.contains('»'));
  }

  #[test]
  fn attachment_match_carries_kind_and_page_count() {
    let (_dir, path) = attachment_store();
    let photo = search(&path, json!({ "query": "'ocr hit" }));
    let matched = &photo[0]["matches"][0];
    assert_eq!(matched["kind"], "photo");
    assert_eq!(matched["attachment_identifier"], "att-1");
    assert!(matched.get("page_count").is_none());
    assert!(matched["excerpt"].as_str().unwrap().contains('«'));

    let body = search(&path, json!({ "query": "alpha unique" }));
    assert!(body[0]["matches"][0].get("kind").is_none());
    assert!(body[0]["matches"][0].get("page_count").is_none());

    let conn = rusqlite::Connection::open(&path).unwrap();
    conn
      .execute(
        "UPDATE ZICCLOUDSYNCINGOBJECT
         SET ZTYPEUTI = 'com.apple.paper.doc.scan', ZMEDIA = NULL, ZFALLBACKPDFGENERATION = '226_GEN',
             ZTITLE = NULL, ZSUMMARY = NULL, ZHANDWRITINGSUMMARY = NULL, ZURLSTRING = NULL,
             ZOCRSUMMARY = 'deposit due on page two'
         WHERE ZIDENTIFIER = 'att-1'",
        [],
      )
      .unwrap();
    drop(conn);
    let pdf = path
      .parent()
      .unwrap()
      .join("Accounts/acct-1/FallbackPDFs/att-1/226_GEN/FallbackPDF.pdf");
    std::fs::create_dir_all(pdf.parent().unwrap()).unwrap();
    std::fs::write(&pdf, two_page_pdf()).unwrap();
    touch_store(&path);

    let scan = search(&path, json!({ "query": "'deposit" }));
    let matched = &scan[0]["matches"][0];
    assert_eq!(matched["kind"], "scan");
    assert_eq!(matched["page_count"], 2);
    assert_eq!(matched["attachment_identifier"], "att-1");
    assert_eq!(matched["excerpt"], "«deposit» due on page two");

    std::fs::write(&pdf, b"%PDF-1.4\nno page tree\n").unwrap();
    let omitted = search(&path, json!({ "query": "'deposit" }));
    assert_eq!(omitted[0]["matches"][0]["kind"], "scan");
    assert!(omitted[0]["matches"][0].get("page_count").is_none());
  }

  #[test]
  fn one_match_per_attachment_and_body_joins_different_lines() {
    let (_db, path) = sample_store();
    let conn = rusqlite::Connection::open(&path).unwrap();
    let body = gzip_plain("insurance policy lives here\nclaim number is separate");
    conn
      .execute("UPDATE ZICNOTEDATA SET ZDATA = ?1 WHERE Z_PK = 1017", [body])
      .unwrap();
    conn
      .execute(
        "UPDATE ZICCLOUDSYNCINGOBJECT
         SET ZTITLE = NULL, ZSUMMARY = NULL, ZHANDWRITINGSUMMARY = NULL, ZURLSTRING = NULL,
             ZOCRSUMMARY = 'insurance form line\nclaim id 42'
         WHERE ZIDENTIFIER = 'att-1'",
        [],
      )
      .unwrap();
    conn
      .execute(
        "UPDATE ZICCLOUDSYNCINGOBJECT SET ZFILENAME = NULL WHERE ZIDENTIFIER = 'media-1'",
        [],
      )
      .unwrap();
    drop(conn);

    let notes = search(&path, json!({ "query": "insurance claim" }));
    let body_hit = notes
      .as_array()
      .unwrap()
      .iter()
      .find(|hit| hit["identifier"] == "note-h")
      .expect("body");
    assert_eq!(body_hit["matches"].as_array().unwrap().len(), 1);
    assert_eq!(body_hit["matches"][0]["field"], "body");
    let body_excerpt = body_hit["matches"][0]["excerpt"].as_str().unwrap();
    assert!(body_excerpt.contains("«insurance»"));
    assert!(body_excerpt.contains("«claim»"));
    assert!(body_excerpt.contains('\n'));

    let attachment_hit = notes
      .as_array()
      .unwrap()
      .iter()
      .find(|hit| hit["identifier"] == "note-i")
      .expect("attachment");
    assert_eq!(attachment_hit["matches"].as_array().unwrap().len(), 1);
    let excerpt = attachment_hit["matches"][0]["excerpt"].as_str().unwrap();
    assert!(excerpt.contains("«insurance»"));
    assert!(excerpt.contains("«claim»"));
    assert_eq!(attachment_hit["matches"][0]["attachment_identifier"], "att-1");
  }

  #[test]
  fn note_hits_list_top_level_attachments_in_body_order() {
    let (_dir, path) = attachment_store();
    let hits = search(&path, json!({ "query": "'ocr hit" }));
    let attachments = hits[0]["attachments"].as_array().unwrap();
    let identifiers: Vec<&str> = attachments
      .iter()
      .map(|card| card["identifier"].as_str().unwrap())
      .collect();
    assert_eq!(identifiers, vec!["att-1", "att-gallery"]);
    assert_eq!(attachments[0]["kind"], "photo");
    assert_eq!(attachments[0]["title"], "Beta Unique");
    assert!(attachments[0].get("text").is_none());
    assert!(attachments[0].get("page_count").is_none());
    assert_eq!(attachments[1]["kind"], "gallery");
    assert!(attachments[1].get("title").is_none());
  }

  fn gzip_plain(text: &str) -> Vec<u8> {
    use std::io::Write;

    use flate2::Compression;
    use flate2::write::GzEncoder;
    use prost::Message;

    let document = super::super::proto_note::NoteDocument {
      version: Some(super::super::proto_note::NoteVersion {
        serialization_version: Some(0),
        minimum_supported_version: Some(0),
        data: Some(super::super::proto_note::TopotextString {
          string: Some(text.to_string()),
          attribute_run: Vec::new(),
        }),
      }),
    };
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(&document.encode_to_vec()).unwrap();
    encoder.finish().unwrap()
  }

  fn touch_store(path: &std::path::Path) {
    let file = std::fs::File::options().write(true).open(path).unwrap();
    file.set_modified(SystemTime::now() + Duration::from_secs(3)).unwrap();
  }

  fn two_page_pdf() -> Vec<u8> {
    let mut pdf = Vec::from(&b"%PDF-1.4\n"[..]);
    pdf.extend_from_slice(b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
    pdf.extend_from_slice(b"2 0 obj\n<< /Type /Pages /Count 2 /Kids [3 0 R 4 0 R] >>\nendobj\n");
    pdf.extend_from_slice(b"trailer\n<< /Root 1 0 R >>\n%%EOF\n");
    pdf
  }

  fn clear_attachment_text(path: &std::path::Path, ocr: &str) {
    let conn = rusqlite::Connection::open(path).unwrap();
    conn
      .execute(
        "UPDATE ZICCLOUDSYNCINGOBJECT
         SET ZTITLE = NULL, ZSUMMARY = NULL, ZHANDWRITINGSUMMARY = NULL, ZURLSTRING = NULL, ZOCRSUMMARY = ?1
         WHERE ZIDENTIFIER = 'att-1'",
        [ocr],
      )
      .unwrap();
    conn
      .execute(
        "UPDATE ZICCLOUDSYNCINGOBJECT SET ZFILENAME = NULL WHERE ZIDENTIFIER = 'media-1'",
        [],
      )
      .unwrap();
  }
}

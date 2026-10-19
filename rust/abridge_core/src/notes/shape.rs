//! Agent-facing shapes. Responses carry what an agent reads, links, and acts on; store internals
//! stay out. Null, false, and empty values are left out, so an absent key means null or false.

use serde_json::{Map, Number, Value, json};
use std::collections::HashSet;
use std::path::Path;

use super::markdown;
use super::store::{self, EntityRow, Snapshot, SqlValue};
use super::timefmt;
use super::write::TRASH_FOLDER_TYPE;

/// How much recognized text an attachment shape keeps.
#[derive(Clone, Copy, PartialEq, Eq)]
pub(crate) enum OcrScope {
  /// Note detail: one copy, capped.
  Note,
  /// Attachment get: one copy, uncapped.
  Full,
}

const OCR_NOTE_CHARS: usize = 2000;

/// A note in list and search results: enough to pick it, without its body.
pub(crate) fn note_summary(snap: &Snapshot, note: &EntityRow) -> Map<String, Value> {
  let mut object = Map::new();
  put_text(&mut object, "identifier", store::text(note, "identifier"));
  put_text(&mut object, "title", store::text(note, "title"));
  if let Some(folder) = folder_of(snap, note) {
    object.insert("folder".into(), folder_ref(snap, folder));
  }
  put_date(&mut object, "creation_date", note, "creationDate");
  put_date(&mut object, "modification_date", note, "modificationDate");
  for (key, attribute) in [
    ("is_pinned", "isPinned"),
    ("is_password_protected", "isPasswordProtected"),
    ("has_checklist", "hasChecklist"),
    ("has_checklist_in_progress", "hasChecklistInProgress"),
    ("needs_initial_fetch_from_cloud", "needsInitialFetchFromCloud"),
  ] {
    if store::flag(note, attribute) {
      object.insert(key.into(), Value::Bool(true));
    }
  }
  let attachments = visible_attachments(snap, note)
    .into_iter()
    .filter(|row| store::foreign_key(row, "parentAttachment").is_none())
    .count();
  if attachments > 0 {
    object.insert("attachment_count".into(), json!(attachments));
  }
  put_text(&mut object, "snippet", store::text(note, "snippet"));
  object
}

/// One note to read and act on: the list summary without `snippet`, plus Markdown `body` and the
/// attachments the body references, including gallery pages. Both are omitted when empty.
pub(crate) fn note_detail(store_path: &Path, snap: &Snapshot, note: &EntityRow) -> Value {
  let mut object = note_summary(snap, note);
  object.remove("snippet");
  if let Some(body) = markdown::note_markdown(snap, note).filter(|body| !body.is_empty()) {
    object.insert("body".into(), Value::String(body));
  }
  let attachments = attachment_details(store_path, snap, note);
  if !attachments.is_empty() {
    object.insert("attachments".into(), Value::Array(attachments));
  }
  Value::Object(object)
}

fn attachment_details(store_path: &Path, snap: &Snapshot, note: &EntityRow) -> Vec<Value> {
  visible_attachments(snap, note)
    .into_iter()
    .filter_map(|row| {
      let mut value = attachment_detail(snap, row, OcrScope::Note)?;
      if let Some(size) = super::attachment_file::on_disk_len(store_path, snap, row)
        && let Some(object) = value.as_object_mut()
      {
        object.insert("file_size".into(), Value::from(size));
      }
      Some(value)
    })
    .collect()
}

pub(crate) fn attachment_detail(snap: &Snapshot, row: &EntityRow, ocr: OcrScope) -> Option<Value> {
  let mut object = Map::new();
  put_text(&mut object, "identifier", store::text(row, "identifier"));
  put_text(&mut object, "type_uti", store::text(row, "typeUTI"));
  put_text(&mut object, "title", store::text(row, "title"));
  put_text(&mut object, "file_name", media_filename(snap, row));
  put_positive(&mut object, "file_size", number_of(row, "fileSize"));
  put_text(&mut object, "url", store::text(row, "urlString"));
  put_recognized_text(&mut object, row, ocr);
  put_text(
    &mut object,
    "handwriting_summary",
    store::text(row, "handwritingSummary"),
  );
  put_positive(&mut object, "duration", number_of(row, "duration"));
  if let Some(parent) =
    store::foreign_key(row, "parentAttachment").and_then(|pk| store::row_by_pk(&snap.attachments, pk))
  {
    put_text(&mut object, "parent_identifier", store::text(parent, "identifier"));
  }
  put_date(&mut object, "creation_date", row, "creationDate");
  put_date(&mut object, "modification_date", row, "modificationDate");
  if object.is_empty() {
    None
  } else {
    Some(Value::Object(object))
  }
}

fn media_filename<'a>(snap: &'a Snapshot, row: &EntityRow) -> Option<&'a str> {
  let media = store::row_by_pk(&snap.media, store::foreign_key(row, "media")?)?;
  store::text(media, "filename")
}

fn number_of(row: &EntityRow, attribute: &str) -> Option<f64> {
  match store::non_null(row, attribute)? {
    SqlValue::Int(value) => Some(*value as f64),
    SqlValue::Real(value) if value.is_finite() => Some(*value),
    _ => None,
  }
}

fn put_positive(object: &mut Map<String, Value>, key: &str, value: Option<f64>) {
  let Some(number) = value.filter(|number| *number > 0.0) else {
    return;
  };
  let Some(json) = Number::from_f64(number) else {
    return;
  };
  let value = if number.fract() == 0.0 {
    let whole = number as i64;
    if (whole as f64) == number {
      Value::Number(whole.into())
    } else {
      Value::Number(json)
    }
  } else {
    Value::Number(json)
  };
  object.insert(key.into(), value);
}

/// A folder in `notes_list_folders` and folder writes.
pub(crate) fn folder(snap: &Snapshot, folder: &EntityRow) -> Value {
  let mut object = Map::new();
  put_text(&mut object, "identifier", store::text(folder, "identifier"));
  put_text(&mut object, "name", store::text(folder, "title"));
  object.insert("path".into(), Value::String(folder_path(snap, folder)));
  if store::integer(folder, "folderType") == Some(TRASH_FOLDER_TYPE) {
    object.insert("kind".into(), json!("recently_deleted"));
  } else if store::text(folder, "smartFolderQueryJSON").is_some() {
    object.insert("kind".into(), json!("smart"));
  }
  if let Some(parent) = parent_of(snap, folder) {
    put_text(&mut object, "parent_identifier", store::text(parent, "identifier"));
  }
  if let Some(account) = account_of(snap, folder) {
    let mut account_object = Map::new();
    put_text(&mut account_object, "identifier", store::text(account, "identifier"));
    put_text(&mut account_object, "name", store::text(account, "name"));
    object.insert("account".into(), Value::Object(account_object));
  }
  let notes = snap
    .notes
    .iter()
    .filter(|note| store::foreign_key(note, "folder") == Some(folder.pk))
    .count();
  object.insert("note_count".into(), json!(notes));
  Value::Object(object)
}

/// `{identifier, path}` of the folder a note sits in; the path starts at the account's top level.
pub(crate) fn folder_ref(snap: &Snapshot, folder: &EntityRow) -> Value {
  let mut object = Map::new();
  put_text(&mut object, "identifier", store::text(folder, "identifier"));
  object.insert("path".into(), Value::String(folder_path(snap, folder)));
  if let Some(account) = account_of(snap, folder) {
    put_text(&mut object, "account", store::text(account, "name"));
  }
  Value::Object(object)
}

pub(crate) fn folder_of<'a>(snap: &'a Snapshot, note: &EntityRow) -> Option<&'a EntityRow> {
  store::row_by_pk(&snap.folders, store::foreign_key(note, "folder")?)
}

/// Folder names from the account's top level down, joined with `/`. Parent loops end the walk.
pub(crate) fn folder_path(snap: &Snapshot, folder: &EntityRow) -> String {
  let mut names = vec![store::text(folder, "title").unwrap_or_default()];
  let mut seen = vec![folder.pk];
  let mut current = folder;
  while let Some(parent) = parent_of(snap, current) {
    if seen.contains(&parent.pk) {
      break;
    }
    seen.push(parent.pk);
    names.push(store::text(parent, "title").unwrap_or_default());
    current = parent;
  }
  names.reverse();
  names.join("/")
}

/// Attachments the body still references, plus pages of a referenced gallery. A table is already
/// the Markdown in `body`, so it is not listed again as a file to fetch. Store rows the body no
/// longer mentions stay out.
pub(super) fn visible_attachments<'a>(snap: &'a Snapshot, note: &EntityRow) -> Vec<&'a EntityRow> {
  let ids = markdown::referenced_attachment_identifiers(snap, note);
  let mut rows: Vec<&EntityRow> = snap
    .attachments
    .iter()
    .filter(|row| {
      (store::text(row, "typeUTI") != Some("com.apple.notes.table") || markdown::table_markdown(row).is_none())
        && store::foreign_key(row, "note") == Some(note.pk)
        && store::text(row, "identifier").is_some_and(|identifier| ids.contains(identifier))
    })
    .collect();
  let referenced: HashSet<i64> = rows.iter().map(|row| row.pk).collect();
  let mut seen: HashSet<i64> = referenced.clone();
  for row in &snap.attachments {
    if store::foreign_key(row, "note") != Some(note.pk) {
      continue;
    }
    let Some(parent) = store::foreign_key(row, "parentAttachment") else {
      continue;
    };
    if referenced.contains(&parent) && seen.insert(row.pk) {
      rows.push(row);
    }
  }
  rows.sort_by_key(|row| row.pk);
  rows
}

pub(crate) struct Recognized {
  pub text: String,
  pub summary: Option<String>,
  pub classification: Option<String>,
}

/// OCR text, plus classification when its keyed text is not the OCR text. `summary` is set only
/// when both of those are absent: Apple's summary repeats classification and an OCR snippet, so
/// containment is not a reliable duplicate test.
pub(crate) fn recognized(row: &EntityRow) -> Recognized {
  let text = dedupe_ocr(store::text(row, "ocrSummary").unwrap_or(""));
  let classification = store::text(row, "imageClassificationSummary").and_then(|raw| {
    let body = stored_body(raw);
    if body.is_empty() || same_keyed_text(&body, &text) {
      None
    } else {
      Some(body)
    }
  });
  let summary = if text.is_empty() && classification.is_none() {
    store::text(row, "summary").and_then(|raw| {
      let body = stored_body(raw);
      (!body.is_empty()).then_some(body)
    })
  } else {
    None
  };
  Recognized {
    text,
    summary,
    classification,
  }
}

pub(crate) fn recognized_text(row: &EntityRow) -> String {
  recognized(row).text
}

/// Image classification that is not another copy of the OCR text.
pub(crate) fn image_classification(row: &EntityRow) -> String {
  recognized(row).classification.unwrap_or_default()
}

/// Tab-separated OCR, then a line pass. Fragments are compared as lowercase letters and digits: a
/// fragment is dropped when that key is already inside a kept fragment, and it replaces a kept
/// fragment when the new key contains the kept one. Lines are keyed the same way. A later line is
/// dropped when its key equals an earlier kept key, or is contained in one and the shorter key is
/// at least 4 characters and at least 80% of the longer key's length. When a later key contains an
/// earlier kept key under that same test, the later line replaces the earlier one in place. A line
/// with no letters or digits is kept and is not a match.
pub(crate) fn dedupe_ocr(raw: &str) -> String {
  dedupe_lines(&dedupe_fragments(raw))
}

fn dedupe_fragments(raw: &str) -> String {
  let mut kept: Vec<(String, &str)> = Vec::new();
  for part in raw.split('\t') {
    let trimmed = part.trim();
    if trimmed.is_empty() {
      continue;
    }
    let key = alnum_key(trimmed);
    if key.is_empty() || kept.iter().any(|(existing, _)| existing.contains(&key)) {
      continue;
    }
    kept.retain(|(existing, _)| !key.contains(existing));
    kept.push((key, trimmed));
  }
  kept.into_iter().map(|(_, text)| text).collect::<Vec<_>>().join("\n")
}

fn dedupe_lines(text: &str) -> String {
  let mut kept: Vec<(String, String)> = Vec::new();
  for line in text.split('\n') {
    let trimmed = line.trim();
    if trimmed.is_empty() {
      continue;
    }
    let key = alnum_key(trimmed);
    if kept.iter().any(|(existing, _)| contained_near_copy(&key, existing)) {
      continue;
    }
    if kept.iter().any(|(existing, _)| contained_near_copy(existing, &key)) {
      let mut placed = false;
      kept.retain(|(existing, _)| {
        if !contained_near_copy(existing, &key) {
          return true;
        }
        if placed {
          return false;
        }
        placed = true;
        true
      });
      if let Some((existing, line)) = kept
        .iter_mut()
        .find(|(existing, _)| contained_near_copy(existing, &key))
      {
        *existing = key;
        *line = trimmed.to_string();
      }
      continue;
    }
    kept.push((key, trimmed.to_string()));
  }
  kept.into_iter().map(|(_, line)| line).collect::<Vec<_>>().join("\n")
}

/// `candidate` equals `kept`, or sits inside it, is at least 4 characters, and is at least 80% of
/// its length. Empty keys are not a match.
fn contained_near_copy(candidate: &str, kept: &str) -> bool {
  if candidate.is_empty() || kept.is_empty() {
    return false;
  }
  if candidate == kept {
    return true;
  }
  if !kept.contains(candidate) {
    return false;
  }
  let shorter = candidate.len() as u64;
  let longer = kept.len() as u64;
  shorter >= 4 && shorter * 5 >= longer * 4
}

fn stored_body(raw: &str) -> String {
  let deduped = dedupe_ocr(raw);
  if deduped.is_empty() {
    raw.trim().to_string()
  } else {
    deduped
  }
}

/// True when both texts have the same lowercase letters and digits, and that key is not empty.
fn same_keyed_text(left: &str, right: &str) -> bool {
  let left = alnum_key(left);
  !left.is_empty() && left == alnum_key(right)
}

fn alnum_key(text: &str) -> String {
  text
    .chars()
    .filter(|character| character.is_alphanumeric())
    .flat_map(|character| character.to_lowercase())
    .collect()
}

fn repeats_ocr(candidate: &str, kept: &str) -> bool {
  let key = alnum_key(candidate);
  !key.is_empty() && key == alnum_key(kept)
}

fn cap_chars(text: &str, max_chars: usize) -> (String, bool) {
  if text.chars().count() <= max_chars {
    return (text.to_string(), false);
  }
  let end = text
    .char_indices()
    .nth(max_chars)
    .map(|(index, _)| index)
    .unwrap_or(text.len());
  (text[..end].to_string(), true)
}

fn put_recognized_text(object: &mut Map<String, Value>, row: &EntityRow, scope: OcrScope) {
  let recognized = recognized(row);
  if !recognized.text.is_empty() {
    let (shown, truncated) = if scope == OcrScope::Note {
      cap_chars(&recognized.text, OCR_NOTE_CHARS)
    } else {
      (recognized.text.clone(), false)
    };
    put_text(object, "ocr_summary", Some(&shown));
    if truncated {
      object.insert("ocr_truncated".into(), Value::Bool(true));
    }
  }
  if let Some(summary) = recognized.summary.as_deref() {
    put_text(object, "summary", Some(summary));
  }
  if let Some(classification) = recognized.classification.as_deref() {
    put_text(object, "image_classification_summary", Some(classification));
  }
  if let Some(extra) = store::text(row, "additionalIndexableText")
    && !repeats_ocr(extra, &recognized.text)
  {
    put_text(object, "additional_indexable_text", Some(extra));
  }
}

fn parent_of<'a>(snap: &'a Snapshot, folder: &EntityRow) -> Option<&'a EntityRow> {
  store::row_by_pk(&snap.folders, store::foreign_key(folder, "parent")?)
}

fn account_of<'a>(snap: &'a Snapshot, folder: &EntityRow) -> Option<&'a EntityRow> {
  store::row_by_pk(&snap.accounts, store::foreign_key(folder, "account")?)
}

pub(crate) fn put_text(object: &mut Map<String, Value>, key: &str, value: Option<&str>) {
  if let Some(text) = value.filter(|text| !text.is_empty()) {
    object.insert(key.into(), Value::String(text.to_string()));
  }
}

pub(crate) fn put_date(object: &mut Map<String, Value>, key: &str, row: &EntityRow, attribute: &str) {
  let seconds = match store::non_null(row, attribute) {
    Some(SqlValue::Real(value)) => *value,
    Some(SqlValue::Int(value)) => *value as f64,
    _ => return,
  };
  if let Some(date) = timefmt::core_data_to_rfc3339(seconds) {
    object.insert(key.into(), Value::String(date));
  }
}
#[cfg(test)]
mod tests {
  use super::dedupe_ocr;

  #[test]
  fn dedupe_drops_near_identical_lines_and_keeps_the_longer_reading() {
    assert_eq!(dedupe_ocr("Hello, world!\thello world\tHELLO  WORLD."), "Hello, world!");
    assert_eq!(dedupe_ocr("ab\tabc def"), "abc def");
    assert_eq!(dedupe_ocr("abc def\tab"), "abc def");
    assert_eq!(dedupe_ocr("Alpha line\tAlpha line\tBeta"), "Alpha line\nBeta");
    assert_eq!(dedupe_ocr("Rev. 10\nRev.10\nToken\nToken"), "Rev. 10\nToken");
    assert_eq!(dedupe_ocr("Invoice totals\nInvoice total"), "Invoice totals");
    assert_eq!(dedupe_ocr("Invoice total\nInvoice totals"), "Invoice totals");
    assert_eq!(
      dedupe_ocr("Invoice total\nOther line\nInvoice totals"),
      "Invoice totals\nOther line"
    );
    assert_eq!(dedupe_ocr("Hello\n---\nHello"), "Hello\n---");
  }

  #[test]
  fn dedupe_keeps_a_short_line_that_only_sits_inside_a_longer_one() {
    assert_eq!(dedupe_ocr("Total 12.00\n12.00"), "Total 12.00\n12.00");
    assert_eq!(dedupe_ocr("12.00\nTotal 12.00"), "12.00\nTotal 12.00");
    assert_eq!(dedupe_ocr("Rev 10\n1"), "Rev 10\n1");
    assert_eq!(dedupe_ocr("1\nRev 10"), "1\nRev 10");
    assert_eq!(dedupe_ocr("kept line\nkept"), "kept line\nkept");
  }

  #[test]
  fn summary_is_kept_only_when_ocr_and_classification_are_absent() {
    use super::recognized;
    use crate::notes::store::{EntityRow, SqlValue};
    use std::collections::HashMap;

    fn row(pairs: &[(&str, &str)]) -> EntityRow {
      EntityRow {
        pk: 1,
        values: pairs
          .iter()
          .map(|(column, text)| ((*column).to_string(), SqlValue::Text((*text).to_string())))
          .collect::<HashMap<_, _>>(),
      }
    }

    let with_ocr = recognized(&row(&[
      ("ZOCRSUMMARY", "Total 12.00"),
      ("ZSUMMARY", "12.00 plus a caption"),
    ]));
    assert_eq!(with_ocr.text, "Total 12.00");
    assert!(with_ocr.summary.is_none());

    let classified = recognized(&row(&[
      ("ZIMAGECLASSIFICATIONSUMMARY", "a cat"),
      ("ZSUMMARY", "a cat, then an OCR snippet"),
    ]));
    assert!(classified.text.is_empty());
    assert_eq!(classified.classification.as_deref(), Some("a cat"));
    assert!(classified.summary.is_none());

    let equal_classification = recognized(&row(&[
      ("ZOCRSUMMARY", "Hello, world!"),
      ("ZIMAGECLASSIFICATIONSUMMARY", "hello world"),
      ("ZSUMMARY", "a scene"),
    ]));
    assert_eq!(equal_classification.text, "Hello, world!");
    assert!(equal_classification.classification.is_none());
    assert!(equal_classification.summary.is_none());

    let distinct_classification = recognized(&row(&[
      ("ZOCRSUMMARY", "Alpha line"),
      ("ZIMAGECLASSIFICATIONSUMMARY", "a cat"),
      ("ZSUMMARY", "a cat Alpha line"),
    ]));
    assert_eq!(distinct_classification.text, "Alpha line");
    assert_eq!(distinct_classification.classification.as_deref(), Some("a cat"));
    assert!(distinct_classification.summary.is_none());

    let only_summary = recognized(&row(&[("ZSUMMARY", "only summary")]));
    assert!(only_summary.text.is_empty());
    assert!(only_summary.classification.is_none());
    assert_eq!(only_summary.summary.as_deref(), Some("only summary"));
  }
}

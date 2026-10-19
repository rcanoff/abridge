//! JXA-backed note and folder writes, each confirmed against the store.

use serde_json::Value;
use std::path::Path;
use std::sync::Mutex;

use super::confirm;
use super::error::NotesError;
use super::markdown;
use super::markdown_html;
use super::osascript::{self, NOTE_IN_RECENTLY_DELETED_MESSAGE};
use super::query;
use super::script::{NOTE_CHANGED, NOTE_IN_RECENTLY_DELETED};
use super::shape;
use super::store::{self, EntityRow, Snapshot};

const TABLE_UTI: &str = "com.apple.notes.table";

/// `ICFolder.folderType` of an account's Recently Deleted folder.
pub(crate) const TRASH_FOLDER_TYPE: i64 = 1;

/// One Notes write at a time: each write reads the store, checks it, scripts Notes, and confirms
/// the result. Overlapping writes would act on stale checks (two deletes of one note would make
/// the second erase it from Recently Deleted).
static WRITES: Mutex<()> = Mutex::new(());

pub(super) fn write_lock() -> std::sync::MutexGuard<'static, ()> {
  WRITES.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

pub(crate) fn create_note(path: &Path, arguments: &Value) -> Result<Value, NotesError> {
  super::resolve::check_folder_choice(arguments, true)?;
  let rendered = markdown_html::notes_html(&query::required_string(arguments, "body")?)?;
  let _write = write_lock();
  let snap = store::load(path)?;
  let folder_identifier = super::resolve::required_folder(&snap, arguments)?;
  let folder_uri = uri_for(&snap, "ICFolder", &folder_identifier, "folder not found")?;
  let response = osascript::run(&serde_json::json!({
    "action": "create_note",
    "folder_id": folder_uri,
    "body": rendered.html,
  }))?;
  let unconfirmed = confirm::outcome_unknown(
    "Notes created the note but has not saved it yet; list the folder again shortly instead of creating it again.",
  );
  let confirmed = confirm::created(path, "ICNote", created_pk(&response)?, &unconfirmed)?;
  presented_note(path, confirmed, rendered.warnings, 0)
}

pub(crate) fn update_note(path: &Path, arguments: &Value) -> Result<Value, NotesError> {
  super::resolve::check_note_identity(arguments)?;
  super::resolve::check_folder_choice(arguments, false)?;
  let markdown = query::required_string(arguments, "body")?;
  let _write = write_lock();
  let snap = store::load(path)?;
  let identifier = super::resolve::note_identifier(&snap, arguments)?;
  let note =
    store::row_by_identifier(&snap.notes, &identifier).ok_or_else(|| NotesError::new("not_found", "note not found"))?;
  if let Some(err) = body_unavailable(&snap, note) {
    return Err(err);
  }
  if let Some(err) = replacement_refusal(&snap, note) {
    return Err(err);
  }
  let rendered = markdown_html::notes_html(&markdown)?;
  let mut warnings = rendered.warnings;
  let previous_tables = referenced_table_count(&snap, note);
  if let Some(warning) = table_loss_warning(previous_tables, &rendered.html) {
    warnings.push(warning);
  }
  let stored_markdown = markdown::note_markdown(&snap, note).unwrap_or_default();
  let same_body = markdown_html::notes_html(&stored_markdown)
    .ok()
    .is_some_and(|stored| stored.html == rendered.html);
  if same_body {
    return presented_note(
      path,
      serde_json::json!({ "identifier": identifier }),
      warnings,
      previous_tables,
    );
  }
  let note_uri = uri_for(&snap, "ICNote", &identifier, "note not found")?;
  let modification_ms = modification_unix_ms(note).ok_or_else(|| {
    NotesError::new(
      "note_changed",
      "the note has no modification date, so it cannot be updated safely. Nothing was changed",
    )
  })?;
  let before = query::project_note(&snap, &identifier)?;
  osascript::run(&serde_json::json!({
    "action": "update_note",
    "note_id": note_uri,
    "body": rendered.html,
    "modification_ms": modification_ms,
    "attachment_count": scripting_attachment_count(&snap, note),
    "note_changed_error": NOTE_CHANGED,
  }))?;
  let unconfirmed = confirm::outcome_unknown(
    "Notes accepted the new body but has not saved it yet; get the note again shortly before retrying.",
  );
  let confirmed = confirm::note_until(
    path,
    &identifier,
    |note| note.get("note_data") != before.get("note_data"),
    &unconfirmed,
  )?;
  presented_note(path, confirmed, warnings, previous_tables)
}

pub(crate) fn move_note(path: &Path, arguments: &Value) -> Result<Value, NotesError> {
  super::resolve::check_note_identity(arguments)?;
  super::resolve::check_folder_choice(arguments, true)?;
  let _write = write_lock();
  let snap = store::load(path)?;
  let folder_identifier = super::resolve::required_folder(&snap, arguments)?;
  let identifier = super::resolve::move_source_identifier(&snap, arguments)?;
  let note_uri = uri_for(&snap, "ICNote", &identifier, "note not found")?;
  let folder_uri = uri_for(&snap, "ICFolder", &folder_identifier, "folder not found")?;
  osascript::run(&serde_json::json!({
    "action": "move_note",
    "note_id": note_uri,
    "folder_id": folder_uri,
  }))?;
  let unconfirmed = confirm::outcome_unknown(
    "Notes accepted the move but has not saved it yet; get the note again shortly before retrying.",
  );
  let confirmed = confirm::note_until(
    path,
    &identifier,
    |note| confirm::folder_identifier(note) == Some(folder_identifier.as_str()),
    &unconfirmed,
  )?;
  presented_note(path, confirmed, Vec::new(), 0)
}

/// Notes' Delete moves a note to Recently Deleted; deleting it again there erases it for good.
/// Only the first step is exposed. The script re-checks the note's folder at the moment of
/// deletion, so a note trashed by anyone since this read is refused rather than erased.
pub(crate) fn delete_note(path: &Path, arguments: &Value) -> Result<Value, NotesError> {
  super::resolve::check_note_identity(arguments)?;
  super::resolve::check_folder_choice(arguments, false)?;
  let _write = write_lock();
  let snap = store::load(path)?;
  let identifier = super::resolve::note_identifier(&snap, arguments)?;
  let note_uri = uri_for(&snap, "ICNote", &identifier, "note not found")?;
  if note_in_trash(&snap, &identifier) {
    return Err(NotesError::new(
      "note_in_recently_deleted",
      NOTE_IN_RECENTLY_DELETED_MESSAGE,
    ));
  }
  let trash_folder_ids = trash_folder_uris(&snap)?;
  if trash_folder_ids.is_empty() {
    return Err(NotesError::new(
      "notes_error",
      "the store has no Recently Deleted folder, so deleting cannot be done safely",
    ));
  }
  osascript::run(&serde_json::json!({
    "action": "delete_note",
    "note_id": note_uri,
    "trash_folder_ids": trash_folder_ids,
    "in_trash_error": NOTE_IN_RECENTLY_DELETED,
  }))?;
  let unconfirmed = confirm::outcome_unknown(
    "Notes deleted the note but has not saved it yet; get the note again shortly, and do not delete it again.",
  );
  let confirmed = confirm::note_until(
    path,
    &identifier,
    |note| confirm::in_trash_folder(note, TRASH_FOLDER_TYPE),
    &unconfirmed,
  )?;
  let mut detail = presented_note(path, confirmed, Vec::new(), 0)?;
  if let Some(object) = detail.as_object_mut() {
    object.insert(
      "deletion".to_string(),
      serde_json::Value::String("recently_deleted".to_string()),
    );
  }
  Ok(detail)
}

fn presented_note(
  path: &Path,
  confirmed: Value,
  mut warnings: Vec<String>,
  previous_tables: usize,
) -> Result<Value, NotesError> {
  let Some(identifier) = confirmed
    .get("identifier")
    .and_then(Value::as_str)
    .filter(|value| !value.is_empty())
  else {
    return Err(NotesError::new("notes_error", "confirmed note has no identifier"));
  };
  let snap = store::load(path)?;
  let Some(note) = store::row_by_identifier(&snap.notes, identifier) else {
    return Err(NotesError::new("not_found", "note not found"));
  };
  if previous_tables > 0
    && referenced_table_count(&snap, note) < previous_tables
    && !warnings.iter().any(|warning| warning == TABLE_LOSS_WARNING)
  {
    warnings.push(TABLE_LOSS_WARNING.to_string());
  }
  Ok(with_warnings(shape::note_detail(path, &snap, note), warnings))
}

fn with_warnings(mut detail: Value, warnings: Vec<String>) -> Value {
  if warnings.is_empty() {
    return detail;
  }
  if let Some(object) = detail.as_object_mut() {
    object.insert(
      "warnings".to_string(),
      Value::Array(warnings.into_iter().map(Value::String).collect()),
    );
  }
  detail
}

fn note_in_trash(snap: &Snapshot, identifier: &str) -> bool {
  store::row_by_identifier(&snap.notes, identifier)
    .and_then(|note| store::foreign_key(note, "folder"))
    .and_then(|folder_pk| store::row_by_pk(&snap.folders, folder_pk))
    .is_some_and(is_trash_folder)
}

pub(super) fn is_trash_folder(folder: &store::EntityRow) -> bool {
  store::integer(folder, "folderType") == Some(TRASH_FOLDER_TYPE)
}

fn trash_folder_uris(snap: &Snapshot) -> Result<Vec<String>, NotesError> {
  let uuid = store_uuid(snap)?;
  Ok(
    snap
      .folders
      .iter()
      .filter(|folder| is_trash_folder(folder))
      .map(|folder| coredata_uri(uuid, "ICFolder", folder.pk))
      .collect(),
  )
}

pub(crate) fn coredata_uri(uuid: &str, entity: &str, pk: i64) -> String {
  format!("x-coredata://{uuid}/{entity}/p{pk}")
}

pub(crate) fn pk_from_coredata_id(id: &str) -> Option<i64> {
  let pk = id.rsplit_once("/p")?.1;
  if pk.is_empty() || !pk.chars().all(|character| character.is_ascii_digit()) {
    return None;
  }
  pk.parse().ok()
}

pub(super) fn created_pk(response: &Value) -> Result<i64, NotesError> {
  response
    .get("id")
    .and_then(Value::as_str)
    .and_then(pk_from_coredata_id)
    .ok_or_else(|| NotesError::new("notes_error", "Notes did not report the new object's id"))
}

fn store_uuid(snap: &Snapshot) -> Result<&str, NotesError> {
  snap
    .uuid
    .as_deref()
    .filter(|value| !value.is_empty())
    .ok_or_else(|| NotesError::new("notes_error", "notes store is missing its metadata id"))
}

const TABLE_LOSS_WARNING: &str = "this update removed or converted an existing Notes table to text";

/// Warn both when the replacement omits a table and when Notes saves fewer tables than before.
fn table_loss_warning(previous_tables: usize, html: &str) -> Option<String> {
  (previous_tables > html.matches("<table").count()).then(|| TABLE_LOSS_WARNING.to_string())
}

fn referenced_table_count(snap: &Snapshot, note: &EntityRow) -> usize {
  let referenced = super::markdown::referenced_attachment_identifiers(snap, note);
  snap
    .attachments
    .iter()
    .filter(|row| {
      store::foreign_key(row, "note") == Some(note.pk)
        && store::text(row, "typeUTI") == Some(TABLE_UTI)
        && store::text(row, "identifier").is_some_and(|identifier| referenced.contains(identifier))
    })
    .count()
}

/// Refuse replacement when the body cannot be inspected, including a note still awaiting download.
/// A password-protected note keeps its own error from `replacement_refusal`.
fn body_unavailable(snap: &Snapshot, note: &EntityRow) -> Option<NotesError> {
  if store::flag(note, "isPasswordProtected") {
    return None;
  }
  if store::flag(note, "needsInitialFetchFromCloud") || !markdown::body_is_available(snap, note) {
    return Some(NotesError::new(
      "body_unavailable",
      "the note body is missing, not downloaded, or could not be read, so it cannot be replaced safely. Nothing was changed",
    ));
  }
  None
}

fn modification_unix_ms(note: &EntityRow) -> Option<i64> {
  let seconds = match store::non_null(note, "modificationDate") {
    Some(store::SqlValue::Real(value)) => *value,
    Some(store::SqlValue::Int(value)) => *value as f64,
    _ => return None,
  };
  let unix_ms = (seconds + 978_307_200.0) * 1000.0;
  unix_ms.is_finite().then_some(unix_ms.round() as i64)
}

fn scripting_attachment_count(snap: &Snapshot, note: &EntityRow) -> i64 {
  let count = snap
    .attachments
    .iter()
    .filter(|row| store::foreign_key(row, "note") == Some(note.pk) && !store::flag(row, "markedForDeletion"))
    .count();
  i64::try_from(count).unwrap_or(i64::MAX)
}

/// Notes replaces the whole HTML body. Checklists and every attachment except a table are lost,
/// and neither `body` concatenation nor a paragraph element keeps them. Scripting cannot add or
/// replace a file without inserting it twice, so this refusal leaves the note unchanged.
fn replacement_refusal(snap: &Snapshot, note: &EntityRow) -> Option<NotesError> {
  if store::flag(note, "isPasswordProtected") {
    return Some(NotesError::new(
      "body_would_drop_content",
      "the note is password protected. Notes with files or checklists cannot have their text edited through scripting without losing them. Nothing was changed",
    ));
  }
  let mut parts = Vec::new();
  if store::flag(note, "hasChecklist") || store::flag(note, "hasChecklistInProgress") {
    parts.push("a checklist".to_string());
  }
  parts.extend(blocking_attachment_labels(snap, note));
  if parts.is_empty() {
    return None;
  }
  Some(NotesError::new(
    "body_would_drop_content",
    format!(
      "notes with files or checklists cannot have their text edited through scripting without losing them. Replacing the body would drop {}. Nothing was changed",
      parts.join("; ")
    ),
  ))
}

fn blocking_attachment_labels(snap: &Snapshot, note: &EntityRow) -> Vec<String> {
  shape::visible_attachments(snap, note)
    .into_iter()
    .filter(|row| store::text(row, "typeUTI") != Some(TABLE_UTI))
    .map(|row| attachment_loss_label(snap, row))
    .collect()
}

fn attachment_loss_label(snap: &Snapshot, row: &EntityRow) -> String {
  let name = store::text(row, "title")
    .filter(|title| !title.is_empty())
    .or_else(|| media_filename(snap, row))
    .or_else(|| store::text(row, "typeUTI").filter(|uti| !uti.is_empty()))
    .unwrap_or("attachment");
  match store::text(row, "identifier").filter(|identifier| !identifier.is_empty()) {
    Some(identifier) => format!("{name} ({identifier})"),
    None => name.to_string(),
  }
}

fn media_filename<'a>(snap: &'a Snapshot, row: &EntityRow) -> Option<&'a str> {
  let media = store::row_by_pk(&snap.media, store::foreign_key(row, "media")?)?;
  store::text(media, "filename").filter(|name| !name.is_empty())
}

pub(super) fn uri_for(snap: &Snapshot, entity: &str, identifier: &str, missing: &str) -> Result<String, NotesError> {
  let uuid = store_uuid(snap)?;
  let rows = match entity {
    "ICNote" => &snap.notes,
    "ICFolder" => &snap.folders,
    "ICAccount" => &snap.accounts,
    _ => return Err(NotesError::new("notes_error", "unknown notes entity")),
  };
  let Some(row) = store::row_by_identifier(rows, identifier) else {
    return Err(NotesError::new("not_found", missing));
  };
  Ok(coredata_uri(uuid, entity, row.pk))
}

#[cfg(test)]
mod tests {
  use super::super::fixture::{add_recently_deleted, sample_store};
  use super::{coredata_uri, pk_from_coredata_id, trash_folder_uris};
  use crate::notes::store;

  #[test]
  fn names_every_recently_deleted_folder_for_the_live_check() {
    let (_db, path) = sample_store();
    add_recently_deleted(&path);
    let snap = store::load(&path).expect("store");

    assert_eq!(
      trash_folder_uris(&snap).expect("uris"),
      vec!["x-coredata://TEST-UUID/ICFolder/p90".to_string()]
    );
  }

  #[test]
  fn replacing_a_table_with_text_warns() {
    let (_db, path) = sample_store();
    let snap = store::load(&path).expect("store");
    let table = store::row_by_identifier(&snap.notes, "note-j").expect("table");
    let plain = store::row_by_identifier(&snap.notes, "note-a").expect("note");
    let previous_tables = super::referenced_table_count(&snap, table);
    assert!(super::table_loss_warning(previous_tables, "<div>Right | Left</div>").is_some());
    assert!(super::table_loss_warning(previous_tables, "<table><tr><td>Right</td></tr></table>").is_none());
    assert!(super::table_loss_warning(super::referenced_table_count(&snap, plain), "<div>plain</div>").is_none());
    let result = super::presented_note(
      &path,
      serde_json::json!({"identifier": "note-a"}),
      Vec::new(),
      previous_tables,
    )
    .expect("note");
    assert_eq!(result["warnings"], serde_json::json!([super::TABLE_LOSS_WARNING]));
  }

  #[test]
  fn update_refuses_a_checklist_or_file_and_allows_a_table() {
    let (_db, path) = sample_store();
    let snap = store::load(&path).expect("store");
    let plain = store::row_by_identifier(&snap.notes, "note-a").expect("note");
    assert!(super::replacement_refusal(&snap, plain).is_none());
    let table = store::row_by_identifier(&snap.notes, "note-j").expect("table");
    assert!(super::replacement_refusal(&snap, table).is_none());
    let photo = store::row_by_identifier(&snap.notes, "note-i").expect("photo");
    let lost = super::replacement_refusal(&snap, photo).expect("refused");
    assert_eq!(lost.code, "body_would_drop_content");
    assert!(lost.message.contains("Beta Unique (att-1)"));
    assert!(!lost.message.contains("att-table"));

    let conn = rusqlite::Connection::open(&path).expect("open");
    conn
      .execute_batch(
        "INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZNOTE, ZTYPEUTI, ZTITLE)
         VALUES
           (48, 4, 'att-orphan', 18, 'public.png', '00-abridge-smoke.png'),
           (49, 4, 'att-orphan-table', 18, 'com.apple.notes.table', 'Old table');",
      )
      .expect("orphan rows");
    drop(conn);
    let snap = store::load(&path).expect("store");
    let lost = super::replacement_refusal(&snap, store::row_by_identifier(&snap.notes, "note-i").expect("photo"))
      .expect("refused");
    assert!(lost.message.contains("Beta Unique (att-1)"));
    assert!(!lost.message.contains("att-orphan"));
    assert!(!lost.message.contains("Old table"));
    assert!(!lost.message.contains("00-abridge-smoke"));

    let conn = rusqlite::Connection::open(&path).expect("open");
    conn
      .execute_batch(
        "ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZHASCHECKLIST INTEGER;
         ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZISPASSWORDPROTECTED INTEGER;
         UPDATE ZICCLOUDSYNCINGOBJECT SET ZHASCHECKLIST = 1 WHERE ZIDENTIFIER = 'note-a';
         UPDATE ZICCLOUDSYNCINGOBJECT SET ZISPASSWORDPROTECTED = 1 WHERE ZIDENTIFIER = 'note-b';",
      )
      .expect("flags");
    drop(conn);
    let snap = store::load(&path).expect("store");
    let checklist = super::replacement_refusal(&snap, store::row_by_identifier(&snap.notes, "note-a").expect("note"))
      .expect("checklist");
    assert!(checklist.message.contains("a checklist"));
    assert!(checklist.message.contains("Nothing was changed"));
    assert!(!checklist.message.contains("Beta Unique"));
    let locked = super::replacement_refusal(&snap, store::row_by_identifier(&snap.notes, "note-b").expect("note"))
      .expect("locked");
    assert!(locked.message.contains("password protected"));
    assert!(locked.message.contains("Nothing was changed"));
    assert!(
      locked
        .message
        .contains("cannot have their text edited through scripting")
    );
  }

  #[test]
  fn warnings_are_omitted_when_empty_and_returned_otherwise() {
    let detail = serde_json::json!({ "identifier": "note-a" });
    assert!(
      super::with_warnings(detail.clone(), Vec::new())
        .get("warnings")
        .is_none()
    );
    let warned = super::with_warnings(
      detail,
      vec!["headings are stored as bold text and read back as # / ## headings".to_string()],
    );
    assert_eq!(
      warned["warnings"],
      serde_json::json!(["headings are stored as bold text and read back as # / ## headings"])
    );
  }

  #[test]
  fn update_refuses_an_unreadable_body_before_scripting() {
    use super::super::call_with_store;
    use super::super::osascript::set_runner_for_test;

    let (_db, path) = sample_store();
    let _runner = set_runner_for_test(|_| panic!("scripted an unreadable body"));
    let code = |identifier: &str| {
      call_with_store(
        &path,
        "update_note",
        &serde_json::json!({ "note_identifier": identifier, "body": "replacement" }),
      )
      .expect_err("refused")
      .code
    };
    assert_eq!(code("note-d"), "body_unavailable");
    assert_eq!(code("note-e"), "body_unavailable");
    assert_eq!(code("note-k"), "body_unavailable");

    let conn = rusqlite::Connection::open(&path).expect("fixture db");
    let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
    std::io::Write::write_all(&mut encoder, b"not a note protobuf").expect("gzip");
    let blob = encoder.finish().expect("gzip");
    conn
      .execute("UPDATE ZICNOTEDATA SET ZDATA = ?1 WHERE Z_PK = 1010", [blob])
      .expect("corrupt");
    drop(conn);
    assert_eq!(code("note-a"), "body_unavailable");

    let conn = rusqlite::Connection::open(&path).expect("fixture db");
    let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
    std::io::Write::write_all(&mut encoder, &vec![0u8; 64 * 1024 * 1024 + 1]).expect("zeros");
    let blob = encoder.finish().expect("gzip");
    conn
      .execute("UPDATE ZICNOTEDATA SET ZDATA = ?1 WHERE Z_PK = 1018", [blob])
      .expect("over limit");
    drop(conn);
    assert_eq!(code("note-i"), "body_unavailable");

    let conn = rusqlite::Connection::open(&path).expect("fixture db");
    conn
      .execute_batch(
        "
        ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZNEEDSINITIALFETCHFROMCLOUD INTEGER;
        UPDATE ZICNOTEDATA SET ZDATA = NULL WHERE Z_PK = 1010;
        UPDATE ZICCLOUDSYNCINGOBJECT SET ZNOTEDATA = 1017, ZNEEDSINITIALFETCHFROMCLOUD = 1
          WHERE ZIDENTIFIER = 'note-a';
        ",
      )
      .expect("pending");
    drop(conn);
    assert_eq!(code("note-a"), "body_unavailable");
  }

  #[test]
  fn an_identical_body_succeeds_without_scripting() {
    use super::super::call_with_store;
    use super::super::osascript::set_runner_for_test;

    let (_db, path) = sample_store();
    let current =
      call_with_store(&path, "get_note", &serde_json::json!({ "note_identifier": "note-a" })).expect("note");
    let body = current["body"].as_str().expect("body").to_string();
    let _runner = set_runner_for_test(|_| panic!("scripted an identical body"));
    let updated = call_with_store(
      &path,
      "update_note",
      &serde_json::json!({ "note_identifier": "note-a", "body": body }),
    )
    .expect("unchanged");
    assert_eq!(updated["identifier"], "note-a");
    assert_eq!(updated["body"], current["body"]);
    assert!(updated.get("deletion").is_none());
  }

  #[test]
  fn update_confirms_the_body_and_refuses_a_live_change() {
    use super::super::call_with_store;
    use super::super::confirm::set_test_budget;
    use super::super::osascript::{map_failure, set_runner_for_test};
    use super::super::script::NOTE_CHANGED;
    use std::time::Duration;

    let (_db, path) = sample_store();
    let _budget = set_test_budget(Duration::from_millis(120));
    let store = path.clone();
    let _runner = set_runner_for_test(move |payload| {
      assert_eq!(payload["action"], "update_note");
      assert_eq!(payload["note_id"], "x-coredata://TEST-UUID/ICNote/p10");
      assert_eq!(payload["attachment_count"], 0);
      assert!(payload["modification_ms"].as_i64().is_some());
      assert_eq!(payload["note_changed_error"], NOTE_CHANGED);
      let conn = rusqlite::Connection::open(&store).expect("fixture db");
      conn
        .execute(
          "UPDATE ZICCLOUDSYNCINGOBJECT SET ZMODIFICATIONDATE1 = 5000 WHERE ZIDENTIFIER = 'note-a'",
          [],
        )
        .expect("touch");
      Ok(serde_json::json!({ "id": "x-coredata://TEST-UUID/ICNote/p10" }))
    });
    let unconfirmed = call_with_store(
      &path,
      "update_note",
      &serde_json::json!({ "note_identifier": "note-a", "body": "a different body" }),
    )
    .expect_err("date only");
    assert_eq!(unconfirmed.code, "write_unconfirmed");
    assert!(unconfirmed.message.contains("may have happened"));
    assert!(unconfirmed.message.contains("check before retrying"));
    drop(_runner);

    let store = path.clone();
    let _runner = set_runner_for_test(move |payload| {
      let conn = rusqlite::Connection::open(&store).expect("fixture db");
      conn
        .execute("UPDATE ZICNOTEDATA SET ZDATA = X'00' WHERE Z_PK = 1010", [])
        .expect("body");
      let _ = payload;
      Ok(serde_json::json!({ "id": "x-coredata://TEST-UUID/ICNote/p10" }))
    });
    let updated = call_with_store(
      &path,
      "update_note",
      &serde_json::json!({ "note_identifier": "note-a", "body": "a different body" }),
    )
    .expect("body changed");
    assert_eq!(updated["identifier"], "note-a");
    drop(_runner);

    let _runner = set_runner_for_test(|payload| {
      Err(map_failure(&format!(
        "execution error: Error: {} (-2700)",
        payload["note_changed_error"].as_str().unwrap_or("")
      )))
    });
    let changed = call_with_store(
      &path,
      "update_note",
      &serde_json::json!({ "note_identifier": "note-b", "body": "another body" }),
    )
    .expect_err("live change");
    assert_eq!(changed.code, "note_changed");
    assert!(changed.message.contains("nothing was written"));
  }

  #[test]
  fn move_by_title_uses_the_source_note_and_refuses_a_destination_twin() {
    use super::super::call_with_store;
    use super::super::osascript::set_runner_for_test;

    let (_db, path) = sample_store();
    let conn = rusqlite::Connection::open(&path).expect("fixture db");
    conn
      .execute(
        "INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER, ZMODIFICATIONDATE1)
         VALUES (70, 3, 'note-dest', 'From suffix', 1, 3, 40)",
        [],
      )
      .expect("twin");
    drop(conn);
    let _runner = set_runner_for_test(|_| panic!("scripted an ambiguous move"));
    let ambiguous = call_with_store(
      &path,
      "move_note",
      &serde_json::json!({ "note_title": "From suffix", "folder_identifier": "fold-2" }),
    )
    .expect_err("two sources");
    assert_eq!(ambiguous.code, "note_title_ambiguous");
    drop(_runner);

    let conn = rusqlite::Connection::open(&path).expect("fixture db");
    conn
      .execute("DELETE FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER = 'note-dest'", [])
      .expect("delete twin");
    drop(conn);
    let store = path.clone();
    let _runner = set_runner_for_test(move |payload| {
      assert_eq!(payload["note_id"], "x-coredata://TEST-UUID/ICNote/p10");
      assert_eq!(payload["folder_id"], "x-coredata://TEST-UUID/ICFolder/p3");
      let conn = rusqlite::Connection::open(&store).expect("fixture db");
      conn
        .execute(
          "UPDATE ZICCLOUDSYNCINGOBJECT SET ZFOLDER = 3 WHERE ZIDENTIFIER = 'note-a'",
          [],
        )
        .expect("move");
      Ok(serde_json::json!({ "id": payload["note_id"].as_str().unwrap() }))
    });
    let moved = call_with_store(
      &path,
      "move_note",
      &serde_json::json!({ "note_title": "From suffix", "folder_path": "Notes/Archive" }),
    )
    .expect("moved");
    assert_eq!(moved["identifier"], "note-a");
    assert_eq!(moved["folder"]["identifier"], "fold-2");
  }

  #[test]
  fn delete_reports_recently_deleted() {
    use super::super::call_with_store;
    use super::super::fixture::add_recently_deleted;
    use super::super::osascript::set_runner_for_test;

    let (_db, path) = sample_store();
    add_recently_deleted(&path);
    let store = path.clone();
    let _runner = set_runner_for_test(move |_| {
      let conn = rusqlite::Connection::open(&store).expect("fixture db");
      conn
        .execute(
          "UPDATE ZICCLOUDSYNCINGOBJECT SET ZFOLDER = 90 WHERE ZIDENTIFIER = 'note-a'",
          [],
        )
        .expect("trash");
      Ok(serde_json::json!({ "id": "x-coredata://TEST-UUID/ICNote/p10" }))
    });
    let deleted = call_with_store(
      &path,
      "delete_note",
      &serde_json::json!({ "note_identifier": "note-a" }),
    )
    .expect("deleted");
    assert_eq!(deleted["identifier"], "note-a");
    assert_eq!(deleted["deletion"], "recently_deleted");
    assert_eq!(deleted["folder"]["identifier"], "trash-1");
  }

  #[test]
  fn formats_and_parses_coredata_uris() {
    let uri = coredata_uri("CACFA800-0BC5-4B4D-8FA2-1D677CEEF23C", "ICNote", 65);
    assert_eq!(uri, "x-coredata://CACFA800-0BC5-4B4D-8FA2-1D677CEEF23C/ICNote/p65");
    assert_eq!(pk_from_coredata_id(&uri), Some(65));
    assert_eq!(pk_from_coredata_id("x-coredata://uuid/ICFolder/p"), None);
    assert_eq!(pk_from_coredata_id("notes://1"), None);
  }
}

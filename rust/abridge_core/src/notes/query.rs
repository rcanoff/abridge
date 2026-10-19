//! Store-backed note and folder reads.

use serde_json::Value;
use std::path::Path;

use super::error::NotesError;
use super::project;
use super::shape;
use super::store::{self, EntityRow, Snapshot};
use super::write::TRASH_FOLDER_TYPE;

pub(crate) fn list_folders(path: &Path, arguments: &Value) -> Result<Value, NotesError> {
  let account_identifier = optional_identifier(arguments, "account_identifier")?;
  let snap = store::load(path)?;
  let account_pk = if let Some(identifier) = account_identifier.as_deref() {
    match store::row_by_identifier(&snap.accounts, identifier) {
      Some(account) => Some(account.pk),
      None => return Ok(Value::Array(Vec::new())),
    }
  } else {
    None
  };
  let mut folders: Vec<(String, Value)> = snap
    .folders
    .iter()
    .filter(|folder| !store::flag(folder, "markedForDeletion"))
    .filter(|folder| !store::flag(folder, "needsInitialFetchFromCloud"))
    .filter(|folder| account_pk.is_none_or(|pk| store::foreign_key(folder, "account") == Some(pk)))
    .map(|folder| (shape::folder_path(&snap, folder), shape::folder(&snap, folder)))
    .collect();
  folders.sort_by_key(|(path, _)| path.to_lowercase());
  Ok(Value::Array(folders.into_iter().map(|(_, folder)| folder).collect()))
}

/// Pinned notes first, then the most recently modified. Without a folder, Recently Deleted and
/// notes Notes has not downloaded from iCloud yet are left out, as in Notes' own note list.
pub(crate) fn list_notes(path: &Path, arguments: &Value) -> Result<Value, NotesError> {
  super::resolve::check_folder_choice(arguments, false)?;
  let (limit, offset) = limit_offset(arguments)?;
  let snap = store::load(path)?;
  let folder_identifier = super::resolve::folder_identifier(&snap, arguments)?;
  let mut notes: Vec<&EntityRow> = folder_notes(&snap, folder_identifier.as_deref())
    .filter(|note| folder_identifier.is_some() || in_note_list(&snap, note))
    .collect();
  notes.sort_by(|a, b| {
    let pinned = store::flag(b, "isPinned").cmp(&store::flag(a, "isPinned"));
    pinned.then_with(|| modified(b).total_cmp(&modified(a)))
  });
  let summaries = notes
    .into_iter()
    .skip(offset)
    .take(limit)
    .map(|note| Value::Object(shape::note_summary(&snap, note)))
    .collect();
  Ok(Value::Array(summaries))
}

/// Whether Notes shows the note in its everyday lists: it has a folder, the folder is not
/// Recently Deleted, and the note is not waiting to be downloaded.
pub(crate) fn in_note_list(snap: &Snapshot, note: &EntityRow) -> bool {
  let Some(folder) = shape::folder_of(snap, note) else {
    return false;
  };
  store::integer(folder, "folderType") != Some(TRASH_FOLDER_TYPE)
    && !store::flag(note, "markedForDeletion")
    && !store::flag(note, "needsInitialFetchFromCloud")
}

pub(crate) fn modified(note: &EntityRow) -> f64 {
  match store::non_null(note, "modificationDate") {
    Some(store::SqlValue::Real(value)) => *value,
    Some(store::SqlValue::Int(value)) => *value as f64,
    _ => f64::NEG_INFINITY,
  }
}

pub(crate) fn get_note(path: &Path, arguments: &Value) -> Result<Value, NotesError> {
  super::resolve::check_note_identity(arguments)?;
  super::resolve::check_folder_choice(arguments, false)?;
  let snap = store::load(path)?;
  let identifier = super::resolve::note_identifier(&snap, arguments)?;
  let Some(note) = store::row_by_identifier(&snap.notes, &identifier) else {
    return Err(NotesError::new("not_found", "note not found"));
  };
  Ok(shape::note_detail(path, &snap, note))
}

pub(crate) fn project_note(snap: &Snapshot, identifier: &str) -> Result<Value, NotesError> {
  let Some(note) = store::row_by_identifier(&snap.notes, identifier) else {
    return Err(NotesError::new("not_found", "note not found"));
  };
  Ok(project::note(snap, note))
}

/// Notes in store order, limited to one folder when `folder_identifier` is given. An unknown
/// folder yields no notes.
fn folder_notes<'a>(snap: &'a Snapshot, folder_identifier: Option<&str>) -> impl Iterator<Item = &'a EntityRow> {
  let folder_pk =
    folder_identifier.map(|identifier| store::row_by_identifier(&snap.folders, identifier).map(|row| row.pk));
  snap.notes.iter().filter(move |note| match folder_pk {
    None => true,
    Some(None) => false,
    Some(Some(pk)) => store::foreign_key(note, "folder") == Some(pk),
  })
}

pub(crate) fn optional_identifier(arguments: &Value, key: &str) -> Result<Option<String>, NotesError> {
  match arguments.get(key) {
    None | Some(Value::Null) => Ok(None),
    Some(Value::String(value)) if has_text(value) => Ok(Some(value.clone())),
    _ => Err(NotesError::new("notes_error", format!("invalid {key}"))),
  }
}

pub(crate) fn required_identifier(arguments: &Value, key: &str) -> Result<String, NotesError> {
  optional_identifier(arguments, key)?.ok_or_else(|| NotesError::new("notes_error", format!("invalid {key}")))
}

pub(crate) fn required_string(arguments: &Value, key: &str) -> Result<String, NotesError> {
  match arguments.get(key) {
    Some(Value::String(value)) => Ok(value.clone()),
    _ => Err(NotesError::new("notes_error", format!("invalid {key}"))),
  }
}

pub(crate) fn limit_offset(arguments: &Value) -> Result<(usize, usize), NotesError> {
  let limit = match arguments.get("limit") {
    None | Some(Value::Null) => 50,
    Some(value) => bounded_u64(value, 1, 200, "limit")?,
  };
  let offset = match arguments.get("offset") {
    None | Some(Value::Null) => 0,
    Some(value) => bounded_u64(value, 0, u64::MAX, "offset")?,
  };
  Ok((limit as usize, offset as usize))
}

fn bounded_u64(value: &Value, minimum: u64, maximum: u64, key: &str) -> Result<u64, NotesError> {
  let Some(number) = value.as_u64() else {
    return Err(NotesError::new("notes_error", format!("invalid {key}")));
  };
  if number < minimum || number > maximum {
    return Err(NotesError::new("notes_error", format!("invalid {key}")));
  }
  Ok(number)
}

fn has_text(value: &str) -> bool {
  value.chars().any(|character| !character.is_whitespace())
}

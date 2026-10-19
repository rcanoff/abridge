//! Resolve `folder_path` and `note_title` to the identifiers the store and Notes scripting use.
//!
//! `folder_path` is the `path` `notes_list_folders` returns. `note_title` is an exact,
//! case-insensitive match against live notes.

use serde_json::Value;

use super::error::NotesError;
use super::query;
use super::shape;
use super::store::{self, EntityRow, Snapshot};
use super::timefmt;
use super::write::TRASH_FOLDER_TYPE;

pub(crate) const FOLDER_EXACTLY_ONE: &str = "Provide exactly one of folder_identifier or folder_path.";
pub(crate) const ACCOUNT_ONLY_WITH_PATH: &str = "account_identifier applies only with folder_path.";
pub(crate) const NOTE_EXACTLY_ONE: &str = "Provide exactly one of note_identifier or note_title.";
pub(crate) const CREATE_FOLDER_PARENT: &str = "Provide an account_identifier, a folder_identifier, or a folder_path. \
account_identifier may accompany folder_path.";

const TITLE_CANDIDATES: usize = 10;

pub(crate) enum FolderParent {
  Account(String),
  Folder(String),
}

/// Rejects a folder choice that is not zero-or-one (`required` false) or exactly one (`required` true).
/// `account_identifier` is allowed only beside `folder_path`.
pub(crate) fn check_folder_choice(arguments: &Value, required: bool) -> Result<(), NotesError> {
  let FolderChoice {
    identifier,
    path,
    account,
  } = folder_fields(arguments)?;
  if identifier.is_some() && path.is_some() {
    return Err(choice_error(FOLDER_EXACTLY_ONE));
  }
  if account.is_some() && path.is_none() {
    return Err(choice_error(ACCOUNT_ONLY_WITH_PATH));
  }
  if required && identifier.is_none() && path.is_none() {
    return Err(choice_error(FOLDER_EXACTLY_ONE));
  }
  Ok(())
}

pub(crate) fn check_note_identity(arguments: &Value) -> Result<(), NotesError> {
  let identifier = query::optional_identifier(arguments, "note_identifier")?;
  let title = query::optional_identifier(arguments, "note_title")?;
  if identifier.is_some() == title.is_some() {
    return Err(choice_error(NOTE_EXACTLY_ONE));
  }
  Ok(())
}

/// `account_identifier` alone creates a top-level folder. `folder_path` may include it to pick an account.
pub(crate) fn check_create_parent(arguments: &Value) -> Result<(), NotesError> {
  let FolderChoice {
    identifier,
    path,
    account,
  } = folder_fields(arguments)?;
  if identifier.is_some() && path.is_some() {
    return Err(choice_error(FOLDER_EXACTLY_ONE));
  }
  let ok = matches!(
    (account.is_some(), identifier.is_some(), path.is_some()),
    (true, false, false) | (false, true, false) | (_, false, true)
  );
  if ok {
    Ok(())
  } else {
    Err(choice_error(CREATE_FOLDER_PARENT))
  }
}

pub(crate) fn folder_identifier(snap: &Snapshot, arguments: &Value) -> Result<Option<String>, NotesError> {
  let FolderChoice {
    identifier,
    path,
    account,
  } = folder_fields(arguments)?;
  if let Some(identifier) = identifier {
    return Ok(Some(identifier));
  }
  let Some(path) = path else {
    return Ok(None);
  };
  Ok(Some(resolve_path(snap, &path, account.as_deref())?))
}

pub(crate) fn required_folder(snap: &Snapshot, arguments: &Value) -> Result<String, NotesError> {
  folder_identifier(snap, arguments)?.ok_or_else(|| choice_error(FOLDER_EXACTLY_ONE))
}

pub(crate) fn create_parent(snap: &Snapshot, arguments: &Value) -> Result<FolderParent, NotesError> {
  let FolderChoice {
    identifier,
    path,
    account,
  } = folder_fields(arguments)?;
  match (account, identifier, path) {
    (Some(account), None, None) => Ok(FolderParent::Account(account)),
    (None, Some(identifier), None) => Ok(FolderParent::Folder(identifier)),
    (account, None, Some(path)) => Ok(FolderParent::Folder(resolve_path(snap, &path, account.as_deref())?)),
    _ => Err(choice_error(CREATE_FOLDER_PARENT)),
  }
}

/// One note identifier. A title matches live notes, excluding Recently Deleted unless `folder`
/// is that folder. Several matches are `note_title_ambiguous`.
pub(crate) fn note_identifier(snap: &Snapshot, arguments: &Value) -> Result<String, NotesError> {
  resolve_note(snap, arguments, true)
}

/// Source note for a move. `folder_*` is only the destination, so a title is resolved across
/// live folders. Several matches are still `note_title_ambiguous`.
pub(crate) fn move_source_identifier(snap: &Snapshot, arguments: &Value) -> Result<String, NotesError> {
  resolve_note(snap, arguments, false)
}

fn resolve_note(snap: &Snapshot, arguments: &Value, scope_folder: bool) -> Result<String, NotesError> {
  let identifier = query::optional_identifier(arguments, "note_identifier")?;
  let title = query::optional_identifier(arguments, "note_title")?;
  let folder = if scope_folder {
    folder_identifier(snap, arguments)?
  } else {
    None
  };
  match (identifier, title) {
    (Some(identifier), None) => Ok(identifier),
    (None, Some(title)) => resolve_title(snap, &title, folder.as_deref()),
    _ => Err(choice_error(NOTE_EXACTLY_ONE)),
  }
}

struct FolderChoice {
  identifier: Option<String>,
  path: Option<String>,
  account: Option<String>,
}

fn folder_fields(arguments: &Value) -> Result<FolderChoice, NotesError> {
  Ok(FolderChoice {
    identifier: query::optional_identifier(arguments, "folder_identifier")?,
    path: query::optional_identifier(arguments, "folder_path")?,
    account: query::optional_identifier(arguments, "account_identifier")?,
  })
}

fn choice_error(message: &str) -> NotesError {
  NotesError::new("notes_error", message)
}

struct ListedFolder {
  path: String,
  identifier: String,
}

fn resolve_path(snap: &Snapshot, wanted: &str, account: Option<&str>) -> Result<String, NotesError> {
  if let Some(account_id) = account {
    let known = snap
      .accounts
      .iter()
      .any(|row| store::text(row, "identifier") == Some(account_id));
    if !known {
      return Err(NotesError::new("not_found", "account not found"));
    }
  }
  let listed = listed_folders(snap, account);
  let matches: Vec<&ListedFolder> = listed.iter().filter(|folder| same_text(&folder.path, wanted)).collect();
  if matches.is_empty() {
    return Err(NotesError::new(
      "folder_path_not_found",
      path_not_found_message(wanted, account, &listed),
    ));
  }
  if matches.len() == 1 {
    return Ok(matches[0].identifier.clone());
  }
  Err(NotesError::new(
    "folder_path_ambiguous",
    path_ambiguous_message(wanted, &matches, account.is_some()),
  ))
}

fn listed_folders(snap: &Snapshot, account: Option<&str>) -> Vec<ListedFolder> {
  let mut folders: Vec<ListedFolder> = snap
    .folders
    .iter()
    .filter(|folder| is_listed_folder(folder))
    .filter_map(|folder| {
      let identifier = store::text(folder, "identifier")?.to_string();
      if account.is_some_and(|account| account_identifier(snap, folder) != Some(account)) {
        return None;
      }
      Some(ListedFolder {
        path: shape::folder_path(snap, folder),
        identifier,
      })
    })
    .collect();
  folders.sort_by(|left, right| {
    left
      .path
      .to_lowercase()
      .cmp(&right.path.to_lowercase())
      .then_with(|| left.identifier.cmp(&right.identifier))
  });
  folders
}

/// Folders `notes_list_folders` returns. A path can only name one of these.
fn is_listed_folder(folder: &EntityRow) -> bool {
  !store::flag(folder, "markedForDeletion") && !store::flag(folder, "needsInitialFetchFromCloud")
}

fn account_identifier<'a>(snap: &'a Snapshot, folder: &EntityRow) -> Option<&'a str> {
  let pk = store::foreign_key(folder, "account")?;
  store::text(store::row_by_pk(&snap.accounts, pk)?, "identifier")
}

fn path_not_found_message(wanted: &str, account: Option<&str>, listed: &[ListedFolder]) -> String {
  let mut message = match account {
    Some(account) => format!("no folder at \"{wanted}\" in account {account}."),
    None => format!("no folder at \"{wanted}\"."),
  };
  push_candidates(&mut message, listed.iter().map(folder_candidate).collect());
  message
}

fn path_ambiguous_message(wanted: &str, matches: &[&ListedFolder], account_was_set: bool) -> String {
  let mut message = format!("\"{wanted}\" matches more than one folder.");
  push_candidates(&mut message, matches.iter().copied().map(folder_candidate).collect());
  if !account_was_set {
    message.push_str(" Pass account_identifier to choose one.");
  }
  message
}

fn folder_candidate(folder: &ListedFolder) -> String {
  format!("{} ({})", folder.path, folder.identifier)
}

fn resolve_title(snap: &Snapshot, title: &str, folder_identifier: Option<&str>) -> Result<String, NotesError> {
  let folder_pk = match folder_identifier {
    Some(identifier) => {
      let folder = store::row_by_identifier(&snap.folders, identifier)
        .ok_or_else(|| NotesError::new("not_found", "folder not found"))?;
      Some(folder.pk)
    }
    None => None,
  };
  let mut matches: Vec<&EntityRow> = snap
    .notes
    .iter()
    .filter(|note| title_in_scope(snap, note, folder_pk))
    .filter(|note| store::text(note, "title").is_some_and(|stored| same_text(stored, title)))
    .collect();
  if matches.is_empty() {
    return Err(NotesError::new("not_found", format!("no note titled \"{title}\"")));
  }
  if matches.len() == 1 {
    return Ok(note_identifier_of(matches[0]).to_string());
  }
  matches.sort_by(|left, right| {
    query::modified(right)
      .total_cmp(&query::modified(left))
      .then_with(|| note_identifier_of(left).cmp(note_identifier_of(right)))
  });
  Err(NotesError::new(
    "note_title_ambiguous",
    title_ambiguous_message(snap, title, &matches),
  ))
}

/// Live notes only. Recently Deleted is included only when the caller named that folder.
fn title_in_scope(snap: &Snapshot, note: &EntityRow, folder_pk: Option<i64>) -> bool {
  if store::flag(note, "markedForDeletion") || store::flag(note, "needsInitialFetchFromCloud") {
    return false;
  }
  let Some(folder) = shape::folder_of(snap, note) else {
    return false;
  };
  if let Some(pk) = folder_pk {
    return folder.pk == pk;
  }
  store::integer(folder, "folderType") != Some(TRASH_FOLDER_TYPE)
}

fn title_ambiguous_message(snap: &Snapshot, title: &str, matches: &[&EntityRow]) -> String {
  let extra = matches.len().saturating_sub(TITLE_CANDIDATES);
  let listed = matches
    .iter()
    .take(TITLE_CANDIDATES)
    .map(|note| note_candidate(snap, note))
    .collect::<Vec<_>>()
    .join("; ");
  if extra > 0 {
    format!("\"{title}\" matches more than one note. Candidates: {listed}; and {extra} more.")
  } else {
    format!("\"{title}\" matches more than one note. Candidates: {listed}.")
  }
}

fn note_candidate(snap: &Snapshot, note: &EntityRow) -> String {
  let identifier = note_identifier_of(note);
  let path = shape::folder_of(snap, note)
    .map(|folder| shape::folder_path(snap, folder))
    .unwrap_or_default();
  match modification_label(note) {
    Some(modified) => format!("{identifier} in {path}, modified {modified}"),
    None => format!("{identifier} in {path}"),
  }
}

fn note_identifier_of(note: &EntityRow) -> &str {
  store::text(note, "identifier").unwrap_or("")
}

fn modification_label(note: &EntityRow) -> Option<String> {
  let seconds = match store::non_null(note, "modificationDate") {
    Some(store::SqlValue::Real(value)) => *value,
    Some(store::SqlValue::Int(value)) => *value as f64,
    _ => return None,
  };
  timefmt::core_data_to_rfc3339(seconds)
}

fn push_candidates(message: &mut String, candidates: Vec<String>) {
  if candidates.is_empty() {
    return;
  }
  message.push_str(" Candidates: ");
  message.push_str(&candidates.join("; "));
  message.push('.');
}

fn same_text(left: &str, right: &str) -> bool {
  left.to_lowercase() == right.to_lowercase()
}

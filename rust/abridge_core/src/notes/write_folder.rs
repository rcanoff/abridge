//! JXA-backed folder creation and deletion. Creation checks Notes' sibling-name rule first.
//! Deletion refuses folders Notes itself will not remove.

use serde_json::Value;
use std::path::Path;

use super::confirm;
use super::error::NotesError;
use super::osascript;
use super::query;
use super::script::FOLDER_NOT_EMPTY;
use super::shape;
use super::store::{self, EntityRow, Snapshot};
use super::write::{created_pk, is_trash_folder, uri_for, write_lock};

pub(crate) fn create_folder(path: &Path, arguments: &Value) -> Result<Value, NotesError> {
  let name = query::required_identifier(arguments, "name")?;
  super::resolve::check_create_parent(arguments)?;
  let _write = write_lock();
  let snap = store::load(path)?;
  let (parent_key, parent_entity, parent_identifier, missing) = match super::resolve::create_parent(&snap, arguments)? {
    super::resolve::FolderParent::Account(account) => ("account_id", "ICAccount", account, "account not found"),
    super::resolve::FolderParent::Folder(folder) => ("parent_id", "ICFolder", folder, "folder not found"),
  };
  let parent_uri = uri_for(&snap, parent_entity, &parent_identifier, missing)?;
  ensure_folder_name_free(&snap, parent_entity, &parent_identifier, &name)?;
  let mut payload = serde_json::json!({
    "action": "create_folder",
    "name": name,
  });
  payload[parent_key] = Value::String(parent_uri);
  let response = osascript::run(&payload)?;
  let unconfirmed = confirm::outcome_unknown(
    "Notes created the folder but has not saved it yet; list folders again shortly instead of creating it again.",
  );
  let confirmed = confirm::created(path, "ICFolder", created_pk(&response)?, &unconfirmed)?;
  let Some(identifier) = confirmed
    .get("identifier")
    .and_then(Value::as_str)
    .filter(|value| !value.is_empty())
  else {
    return Err(NotesError::new("notes_error", "confirmed folder has no identifier"));
  };
  let snap = store::load(path)?;
  let Some(folder) = store::row_by_identifier(&snap.folders, identifier) else {
    return Err(NotesError::new("not_found", "folder not found"));
  };
  Ok(shape::folder(&snap, folder))
}

/// Notes refuses a folder whose name exactly matches (case-sensitive) a sibling's, failing with
/// a bare "Duplicate folder name" (-10000). Check first so the caller learns which folder holds
/// the name. Siblings are the account's top-level folders or the parent folder's children.
fn ensure_folder_name_free(
  snap: &Snapshot,
  parent_entity: &str,
  parent_identifier: &str,
  name: &str,
) -> Result<(), NotesError> {
  let rows = if parent_entity == "ICAccount" {
    &snap.accounts
  } else {
    &snap.folders
  };
  let Some(parent_pk) = store::row_by_identifier(rows, parent_identifier).map(|row| row.pk) else {
    return Ok(());
  };
  let taken = snap.folders.iter().find(|folder| {
    let sibling = if parent_entity == "ICAccount" {
      store::foreign_key(folder, "account") == Some(parent_pk) && store::foreign_key(folder, "parent").is_none()
    } else {
      store::foreign_key(folder, "parent") == Some(parent_pk)
    };
    sibling
      && !is_trash_folder(folder)
      && !store::flag(folder, "markedForDeletion")
      && store::text(folder, "title") == Some(name)
  });
  match taken {
    Some(folder) => Err(folder_name_taken(name, store::text(folder, "identifier"))),
    None => Ok(()),
  }
}

/// Deletes an empty user folder. After the script returns, keeps polling the store until the row
/// is gone or marked for deletion, then returns `{folder_identifier}`. Notes can report the
/// folder gone while a following list still shows it.
pub(crate) fn delete_folder(path: &Path, arguments: &Value) -> Result<Value, NotesError> {
  super::resolve::check_folder_choice(arguments, true)?;
  let _write = write_lock();
  let snap = store::load(path)?;
  let identifier = super::resolve::required_folder(&snap, arguments)?;
  let Some(folder) = store::row_by_identifier(&snap.folders, &identifier) else {
    return Err(NotesError::new("not_found", "folder not found"));
  };
  ensure_deletable(&snap, folder)?;
  let folder_uri = uri_for(&snap, "ICFolder", &identifier, "folder not found")?;
  osascript::run(&serde_json::json!({
    "action": "delete_folder",
    "folder_id": folder_uri,
    "folder_not_empty_error": FOLDER_NOT_EMPTY,
  }))?;
  confirm::folder_deleted(
    path,
    &identifier,
    "Notes has deleted this folder in memory but has not saved it, so it is still listed. Wait for Notes to save; deleting it again fails because Notes no longer has the folder",
  )?;
  Ok(serde_json::json!({ "folder_identifier": identifier }))
}

fn ensure_deletable(snap: &Snapshot, folder: &EntityRow) -> Result<(), NotesError> {
  if is_trash_folder(folder) {
    return Err(NotesError::new(
      "folder_recently_deleted",
      "Recently Deleted cannot be deleted",
    ));
  }
  if store::text(folder, "smartFolderQueryJSON").is_some() {
    return Err(NotesError::new("folder_smart", "smart folders cannot be deleted"));
  }
  if store::text(folder, "identifier").is_some_and(|identifier| identifier.starts_with("DefaultFolder")) {
    return Err(NotesError::new(
      "folder_is_default",
      "the account's default folder cannot be deleted",
    ));
  }
  if holds_notes_or_subfolders(snap, folder) {
    return Err(NotesError::new(
      "folder_not_empty",
      "the folder still holds notes or subfolders; move or delete those first",
    ));
  }
  Ok(())
}

fn holds_notes_or_subfolders(snap: &Snapshot, folder: &EntityRow) -> bool {
  let notes = snap
    .notes
    .iter()
    .any(|note| store::foreign_key(note, "folder") == Some(folder.pk) && !store::flag(note, "markedForDeletion"));
  let subfolders = snap
    .folders
    .iter()
    .any(|child| store::foreign_key(child, "parent") == Some(folder.pk) && !store::flag(child, "markedForDeletion"));
  notes || subfolders
}

fn folder_name_taken(name: &str, existing: Option<&str>) -> NotesError {
  let message = match existing {
    Some(identifier) => format!("a folder named \"{name}\" already exists here; its folder_identifier is {identifier}"),
    None => format!("a folder named \"{name}\" already exists here"),
  };
  NotesError::new("folder_name_taken", message)
}

#[cfg(test)]
mod tests {
  use super::super::fixture::{add_recently_deleted, sample_store};
  use super::ensure_folder_name_free;
  use crate::notes::store;

  #[test]
  fn recently_deleted_does_not_hold_its_name() {
    let (_db, path) = sample_store();
    add_recently_deleted(&path);
    let snap = store::load(&path).expect("store");

    assert!(ensure_folder_name_free(&snap, "ICAccount", "acct-1", "Recently Deleted").is_ok());
    assert!(ensure_folder_name_free(&snap, "ICAccount", "acct-1", "notes").is_ok());
    assert_eq!(
      ensure_folder_name_free(&snap, "ICAccount", "acct-1", "Notes")
        .unwrap_err()
        .code,
      "folder_name_taken"
    );
  }

  #[test]
  fn delete_folder_refuses_protected_and_non_empty_folders() {
    use super::super::call_with_store;
    use rusqlite::Connection;

    let (_db, path) = sample_store();
    add_recently_deleted(&path);
    let conn = Connection::open(&path).expect("fixture db");
    conn
      .execute_batch(
        "
        ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZSMARTFOLDERQUERYJSON TEXT;
        INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZACCOUNT8)
          VALUES (80, 2, 'fold-empty', 'Empty', 1);
        INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZACCOUNT8, ZSMARTFOLDERQUERYJSON)
          VALUES (81, 2, 'fold-smart', 'Smart', 1, '{}');
        INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZACCOUNT8)
          VALUES (82, 2, 'DefaultFolder-CloudKit', 'Notes', 1);
        INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZACCOUNT8)
          VALUES (83, 2, 'fold-parent', 'Parent', 1);
        INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZACCOUNT8, ZPARENT)
          VALUES (84, 2, 'fold-child', 'Child', 1, 83);
        ",
      )
      .expect("folder rows");

    let code = |identifier: &str| {
      call_with_store(
        &path,
        "delete_folder",
        &serde_json::json!({ "folder_identifier": identifier }),
      )
      .unwrap_err()
      .code
    };
    assert_eq!(code("missing"), "not_found");
    assert_eq!(code("fold-1"), "folder_not_empty");
    assert_eq!(code("fold-parent"), "folder_not_empty");
    assert_eq!(code("trash-1"), "folder_recently_deleted");
    assert_eq!(code("fold-smart"), "folder_smart");
    assert_eq!(code("DefaultFolder-CloudKit"), "folder_is_default");

    let snap = store::load(&path).expect("store");
    let empty = store::row_by_identifier(&snap.folders, "fold-empty").expect("empty");
    assert!(super::ensure_deletable(&snap, empty).is_ok());

    let _runner = crate::notes::osascript::set_runner_for_test(|payload| {
      assert_eq!(payload["folder_id"], "x-coredata://TEST-UUID/ICFolder/p80");
      assert_eq!(
        payload["folder_not_empty_error"],
        super::super::script::FOLDER_NOT_EMPTY
      );
      Err(crate::notes::osascript::map_failure(
        "execution error: Error: ABRIDGE_FOLDER_NOT_EMPTY (-2700)",
      ))
    });
    let live = call_with_store(
      &path,
      "delete_folder",
      &serde_json::json!({ "folder_identifier": "fold-empty" }),
    )
    .expect_err("live children");
    assert_eq!(live.code, "folder_not_empty");
    assert!(live.message.contains("notes or subfolders"));
  }

  #[test]
  fn folder_delete_waits_for_the_store_after_notes_reports_it_gone() {
    use super::super::confirm::{self, folder_deleted_within};
    use rusqlite::Connection;
    use std::time::Duration;

    assert!(!confirm::folder_delete_confirmed(true, false));
    assert!(confirm::folder_delete_confirmed(true, true));
    assert!(confirm::folder_delete_confirmed(false, true));
    assert!(!confirm::folder_delete_confirmed(false, false));

    let (_db, path) = sample_store();
    let unconfirmed = "not saved";
    let err = folder_deleted_within(&path, "fold-1", Duration::ZERO, unconfirmed).unwrap_err();
    assert_eq!(err.code, "folder_delete_unsaved");
    assert!(folder_deleted_within(&path, "missing-folder", Duration::ZERO, unconfirmed).is_ok());

    let conn = Connection::open(&path).expect("fixture db");
    conn
      .execute_batch(
        "
        ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZMARKEDFORDELETION INTEGER;
        UPDATE ZICCLOUDSYNCINGOBJECT SET ZMARKEDFORDELETION = 1 WHERE ZIDENTIFIER = 'fold-1';
        ",
      )
      .expect("mark");
    assert!(folder_deleted_within(&path, "fold-1", Duration::ZERO, unconfirmed).is_ok());
  }
}

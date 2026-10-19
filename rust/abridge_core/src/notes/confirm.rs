//! Confirms a Notes write by polling the store for its specific outcome.
//!
//! Notes saves after the script returns, usually within a fraction of a second. Each write waits
//! for its own postcondition; anything else changing in the store does not count, and a write
//! whose outcome never appears fails with `write_unconfirmed` instead of reporting stale data.

use serde_json::Value;
use std::path::Path;
use std::thread;
use std::time::{Duration, Instant};

#[cfg(test)]
use std::cell::Cell;

use super::error::NotesError;
use super::project;
use super::query;
use super::store;

const BUDGET: Duration = Duration::from_secs(5);
/// Folder deletes show up in Notes immediately and in the store a little later. Wait longer than a
/// note write. Notes' own report that the folder is gone is not enough: the row can still be
/// listed for a few seconds.
pub(crate) const FOLDER_DELETE_BUDGET: Duration = Duration::from_secs(20);
const STEP: Duration = Duration::from_millis(50);

/// A folder delete is done only when the store row is gone or marked for deletion. `script_gone`
/// is accepted so callers can show that a scripting report alone does not finish the delete.
pub(crate) fn folder_delete_confirmed(script_gone: bool, store_gone: bool) -> bool {
  let _ = script_gone;
  store_gone
}

/// Polls until `done` holds for the stored note, then returns the note.
pub(crate) fn note_until(
  path: &Path,
  identifier: &str,
  done: impl Fn(&Value) -> bool,
  unconfirmed: &str,
) -> Result<Value, NotesError> {
  poll(path, poll_budget(BUDGET), "write_unconfirmed", unconfirmed, |snap| {
    let note = query::project_note(snap, identifier)?;
    Ok(done(&note).then_some(note))
  })
}

/// Polls until the row Notes reported (`pk` from the script's `x-coredata` id) is stored, then
/// returns it. Only that row counts, never another object that appeared meanwhile.
pub(crate) fn created(path: &Path, entity: &str, pk: i64, unconfirmed: &str) -> Result<Value, NotesError> {
  let entity = entity.to_string();
  poll(
    path,
    poll_budget(BUDGET),
    "write_unconfirmed",
    unconfirmed,
    move |snap| {
      let rows = if entity == "ICNote" { &snap.notes } else { &snap.folders };
      Ok(store::row_by_pk(rows, pk).map(|row| {
        if entity == "ICNote" {
          project::note(snap, row)
        } else {
          project::folder(snap, row)
        }
      }))
    },
  )
}

pub(crate) fn folder_identifier(note: &Value) -> Option<&str> {
  note.pointer("/folder/identifier").and_then(Value::as_str)
}

pub(crate) fn in_trash_folder(note: &Value, trash_folder_type: i64) -> bool {
  note.pointer("/folder/folder_type").and_then(Value::as_i64) == Some(trash_folder_type)
}

/// Polls until the folder row is gone or Notes has marked it for deletion.
pub(crate) fn folder_deleted(path: &Path, identifier: &str, unconfirmed: &str) -> Result<(), NotesError> {
  folder_deleted_within(path, identifier, FOLDER_DELETE_BUDGET, unconfirmed)
}

pub(crate) fn folder_deleted_within(
  path: &Path,
  identifier: &str,
  budget: Duration,
  unconfirmed: &str,
) -> Result<(), NotesError> {
  poll(
    path,
    poll_budget(budget),
    "folder_delete_unsaved",
    unconfirmed,
    |snap| {
      let store_gone = match store::row_by_identifier(&snap.folders, identifier) {
        None => true,
        Some(folder) => store::flag(folder, "markedForDeletion"),
      };
      Ok(folder_delete_confirmed(false, store_gone).then_some(()))
    },
  )
}

/// Retries a locked store until `budget` elapses, then reports `code`. Any other load error
/// returns immediately: it is not evidence the write failed to land, but it is not a lock either.
fn poll<T>(
  path: &Path,
  budget: Duration,
  code: &'static str,
  unconfirmed: &str,
  mut step: impl FnMut(&store::Snapshot) -> Result<Option<T>, NotesError>,
) -> Result<T, NotesError> {
  let deadline = Instant::now() + budget;
  loop {
    match store::load(path) {
      Ok(snap) => {
        if let Some(value) = step(&snap)? {
          return Ok(value);
        }
      }
      Err(err) if store::is_busy(&err) => {}
      Err(err) => return Err(err),
    }
    if Instant::now() >= deadline {
      return Err(NotesError::new(code, unconfirmed));
    }
    thread::sleep(STEP);
  }
}

fn poll_budget(default: Duration) -> Duration {
  #[cfg(test)]
  if let Some(budget) = TEST_BUDGET.with(|cell| cell.get()) {
    return budget;
  }
  default
}

#[cfg(test)]
thread_local! {
  static TEST_BUDGET: Cell<Option<Duration>> = const { Cell::new(None) };
}

/// Shortens confirmation waits on this thread. The real budgets stay in place for other tests.
#[cfg(test)]
pub(crate) struct BudgetGuard;

#[cfg(test)]
impl Drop for BudgetGuard {
  fn drop(&mut self) {
    TEST_BUDGET.with(|cell| cell.set(None));
  }
}

#[cfg(test)]
pub(crate) fn set_test_budget(budget: Duration) -> BudgetGuard {
  TEST_BUDGET.with(|cell| cell.set(Some(budget)));
  BudgetGuard
}

pub(crate) fn outcome_unknown(specific: &str) -> String {
  format!("{specific} The change may have happened; check before retrying")
}

#[cfg(test)]
mod tests {
  use super::{note_until, outcome_unknown, set_test_budget};
  use crate::notes::fixture::sample_store;
  use crate::notes::store;
  use std::time::Duration;

  #[test]
  fn retries_a_locked_store_then_reads_the_note() {
    let (_db, path) = sample_store();
    let _faults = store::fail_next_loads(2);
    let note = note_until(&path, "note-a", |_| true, "unconfirmed").expect("confirmed");
    assert_eq!(note["identifier"], "note-a");
  }

  #[test]
  fn a_lock_that_outlasts_the_budget_is_outcome_unknown() {
    let (_db, path) = sample_store();
    let _faults = store::fail_next_loads(20);
    let _budget = set_test_budget(Duration::ZERO);
    let message = outcome_unknown("Notes accepted the new body but has not saved it yet");
    let err = note_until(&path, "note-a", |_| true, &message).expect_err("still locked");
    assert_eq!(err.code, "write_unconfirmed");
    assert!(err.message.contains("may have happened"));
    assert!(err.message.contains("check before retrying"));
  }

  #[test]
  fn a_missing_store_is_not_retried_as_unconfirmed() {
    let missing = std::env::temp_dir().join(format!("abridge-notes-missing-{}-confirm.sqlite", std::process::id()));
    let _ = std::fs::remove_file(&missing);
    let err = note_until(&missing, "note-a", |_| true, "unconfirmed").expect_err("missing");
    assert_eq!(err.code, "notes_store_not_found");
  }
}

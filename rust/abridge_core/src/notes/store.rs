//! Read-only Notes store snapshots. Callers pass the database path.

use rusqlite::ErrorCode;
use rusqlite::{Connection, OpenFlags, OptionalExtension, params};
use std::collections::HashMap;
use std::path::Path;
use std::time::Duration;

use super::attributes::attributes_for;
use super::columns;
use super::error::NotesError;
use super::rows;

#[derive(Debug)]
pub(crate) struct Snapshot {
  pub uuid: Option<String>,
  pub accounts: Vec<EntityRow>,
  pub folders: Vec<EntityRow>,
  pub notes: Vec<EntityRow>,
  pub attachments: Vec<EntityRow>,
  pub inline_attachments: Vec<EntityRow>,
  pub media: Vec<EntityRow>,
  pub note_data: Vec<NoteDataRow>,
}

#[derive(Debug)]
pub(crate) struct EntityRow {
  pub pk: i64,
  pub values: HashMap<String, SqlValue>,
}

#[derive(Debug)]
pub(crate) enum SqlValue {
  Int(i64),
  Real(f64),
  Text(String),
  Blob(Vec<u8>),
}

#[derive(Debug)]
pub(crate) struct NoteDataRow {
  pub pk: i64,
  pub data: Option<Vec<u8>>,
  pub encrypted: bool,
}

pub(crate) fn load(path: &Path) -> Result<Snapshot, NotesError> {
  #[cfg(test)]
  if take_load_fault() {
    return Err(NotesError::new("notes_error", "database is locked"));
  }
  let conn = open_read_only(path)?;
  // One read transaction: under WAL every SELECT below sees the same commit, so a note never
  // points at a folder or body that Notes wrote between two queries.
  let tx = conn.unchecked_transaction().map_err(rows::map_sql)?;
  let ids = entity_ids(&tx)?;
  let snapshot = Snapshot {
    uuid: store_uuid(&tx)?,
    accounts: load_entity(&tx, ids.get("ICAccount").copied(), "ICAccount", &[])?,
    folders: load_entity(&tx, ids.get("ICFolder").copied(), "ICFolder", &["account", "parent"])?,
    notes: load_entity(
      &tx,
      ids.get("ICNote").copied(),
      "ICNote",
      &["account", "folder", "noteData"],
    )?,
    attachments: load_entity(
      &tx,
      ids.get("ICAttachment").copied(),
      "ICAttachment",
      &["note", "media", "mergeableData", "parentAttachment"],
    )?,
    inline_attachments: load_entity(
      &tx,
      ids.get("ICInlineAttachment").copied(),
      "ICInlineAttachment",
      &["note", "parentAttachment"],
    )?,
    media: load_entity(&tx, ids.get("ICMedia").copied(), "ICMedia", &[])?,
    note_data: load_note_data(&tx)?,
  };
  tx.rollback().map_err(rows::map_sql)?;
  Ok(snapshot)
}

pub(crate) fn non_null<'a>(row: &'a EntityRow, attribute: &str) -> Option<&'a SqlValue> {
  let mut matched = None;
  for (column, value) in &row.values {
    if !columns::is_attribute_column(column, attribute) {
      continue;
    }
    if matched.is_some() {
      tracing::debug!(attribute, column, "multiple non-null note columns");
      return None;
    }
    matched = Some(value);
  }
  matched
}

pub(crate) fn text<'a>(row: &'a EntityRow, attribute: &str) -> Option<&'a str> {
  match non_null(row, attribute)? {
    SqlValue::Text(value) => Some(value.as_str()),
    _ => None,
  }
}

pub(crate) fn foreign_key(row: &EntityRow, relationship: &str) -> Option<i64> {
  match non_null(row, relationship)? {
    SqlValue::Int(value) => Some(*value),
    SqlValue::Real(value) => whole_i64(*value),
    _ => None,
  }
}

pub(crate) fn integer(row: &EntityRow, attribute: &str) -> Option<i64> {
  match non_null(row, attribute)? {
    SqlValue::Int(value) => Some(*value),
    _ => None,
  }
}

pub(crate) fn flag(row: &EntityRow, attribute: &str) -> bool {
  match non_null(row, attribute) {
    Some(SqlValue::Int(value)) => *value != 0,
    _ => false,
  }
}

pub(crate) fn row_by_pk(rows: &[EntityRow], pk: i64) -> Option<&EntityRow> {
  rows.iter().find(|row| row.pk == pk)
}

pub(crate) fn row_by_identifier<'a>(rows: &'a [EntityRow], identifier: &str) -> Option<&'a EntityRow> {
  rows.iter().find(|row| text(row, "identifier") == Some(identifier))
}

fn open_read_only(path: &Path) -> Result<Connection, NotesError> {
  if !path.exists() {
    return Err(NotesError::new("notes_store_not_found", "notes store not found"));
  }
  let conn = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY).map_err(|err| {
    if is_access_error(&err) {
      NotesError::new(
        "full_disk_access_required",
        format!("unable to open notes store: {err}"),
      )
    } else {
      NotesError::new("notes_error", format!("unable to open notes store: {err}"))
    }
  })?;
  conn.execute_batch("PRAGMA query_only=ON").map_err(rows::map_sql)?;
  // A short wait, then the confirm poll retries until its own deadline. A longer timeout here
  // would spend the whole confirmation budget inside one locked read.
  conn.busy_timeout(Duration::from_millis(200)).map_err(rows::map_sql)?;
  Ok(conn)
}

pub(crate) fn is_busy(err: &NotesError) -> bool {
  let message = err.message.to_ascii_lowercase();
  message.contains("database is locked") || message.contains("database is busy") || message.contains("sqlite_busy")
}

#[cfg(test)]
thread_local! {
  static LOAD_FAULTS: std::cell::Cell<u32> = const { std::cell::Cell::new(0) };
}

#[cfg(test)]
fn take_load_fault() -> bool {
  LOAD_FAULTS.with(|cell| {
    let left = cell.get();
    if left == 0 {
      false
    } else {
      cell.set(left - 1);
      true
    }
  })
}

/// The next `times` loads fail as a locked database. Cleared when the guard drops.
#[cfg(test)]
pub(crate) struct LoadFaultGuard;

#[cfg(test)]
impl Drop for LoadFaultGuard {
  fn drop(&mut self) {
    LOAD_FAULTS.with(|cell| cell.set(0));
  }
}

#[cfg(test)]
pub(crate) fn fail_next_loads(times: u32) -> LoadFaultGuard {
  LOAD_FAULTS.with(|cell| cell.set(times));
  LoadFaultGuard
}

fn is_access_error(err: &rusqlite::Error) -> bool {
  match err {
    rusqlite::Error::SqliteFailure(sqlite, _) => matches!(
      sqlite.code,
      ErrorCode::CannotOpen
        | ErrorCode::PermissionDenied
        | ErrorCode::AuthorizationForStatementDenied
        | ErrorCode::SystemIoFailure
    ),
    _ => false,
  }
}

fn entity_ids(conn: &Connection) -> Result<HashMap<String, i64>, NotesError> {
  let mut stmt = conn
    .prepare("SELECT Z_ENT, Z_NAME FROM Z_PRIMARYKEY")
    .map_err(rows::map_sql)?;
  let mut rows = stmt.query(params![]).map_err(rows::map_sql)?;
  let mut ids = HashMap::new();
  while let Some(row) = rows.next().map_err(rows::map_sql)? {
    let ent: i64 = row.get(0).map_err(rows::map_sql)?;
    let name: String = row.get(1).map_err(rows::map_sql)?;
    ids.insert(name, ent);
  }
  Ok(ids)
}

fn store_uuid(conn: &Connection) -> Result<Option<String>, NotesError> {
  let uuid = conn
    .query_row("SELECT Z_UUID FROM Z_METADATA LIMIT 1", params![], |row| {
      row.get::<_, Option<String>>(0)
    })
    .optional()
    .map_err(rows::map_sql)?;
  Ok(uuid.flatten().filter(|value| !value.is_empty()))
}

fn load_entity(
  conn: &Connection,
  ent: Option<i64>,
  entity: &str,
  extra: &[&str],
) -> Result<Vec<EntityRow>, NotesError> {
  let Some(ent) = ent else {
    return Ok(Vec::new());
  };
  let mut names: Vec<&str> = attributes_for(entity).iter().map(|attr| attr.name).collect();
  names.extend(extra);
  rows::read_rows(
    conn,
    "ZICCLOUDSYNCINGOBJECT",
    &names,
    "WHERE Z_ENT = ?1 ORDER BY Z_PK",
    params![ent],
  )
}

fn load_note_data(conn: &Connection) -> Result<Vec<NoteDataRow>, NotesError> {
  let rows = rows::read_rows(conn, "ZICNOTEDATA", &["data", "cryptoTag"], "ORDER BY Z_PK", params![])?;
  Ok(rows.into_iter().map(note_data_row).collect())
}

fn note_data_row(row: EntityRow) -> NoteDataRow {
  let encrypted = non_null(&row, "cryptoTag").is_some();
  let data = if encrypted {
    None
  } else if let Some(SqlValue::Blob(blob)) = non_null(&row, "data") {
    Some(blob.clone())
  } else {
    None
  };
  NoteDataRow {
    pk: row.pk,
    data,
    encrypted,
  }
}

fn whole_i64(value: f64) -> Option<i64> {
  if !value.is_finite() || value.fract() != 0.0 {
    return None;
  }
  Some(value as i64)
}

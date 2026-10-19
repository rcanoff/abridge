//! SQLite column selection for the Notes snapshot.

use rusqlite::types::ValueRef;
use rusqlite::{Connection, Row, params};
use std::collections::HashMap;

use super::columns;
use super::error::NotesError;
use super::store::{EntityRow, SqlValue};

pub(super) fn read_rows(
  conn: &Connection,
  table: &str,
  names: &[&str],
  suffix: &str,
  query_params: impl rusqlite::Params,
) -> Result<Vec<EntityRow>, NotesError> {
  let columns = selected_columns(conn, table, names)?;
  let quoted = columns
    .iter()
    .map(|column| quote_ident(column))
    .collect::<Result<Vec<_>, _>>()?;
  let table = quote_ident(table)?;
  let sql = format!("SELECT {} FROM {table} {suffix}", quoted.join(", "));
  let mut stmt = conn.prepare(&sql).map_err(map_sql)?;
  let mut rows = stmt.query(query_params).map_err(map_sql)?;
  let mut out = Vec::new();
  while let Some(row) = rows.next().map_err(map_sql)? {
    out.push(read_row(row, &columns)?);
  }
  Ok(out)
}

fn selected_columns(conn: &Connection, table: &str, names: &[&str]) -> Result<Vec<String>, NotesError> {
  let mut selected = vec!["Z_PK".to_string()];
  for column in pragma_columns(conn, table)? {
    if column == "Z_PK" {
      continue;
    }
    if names.iter().any(|name| columns::is_attribute_column(&column, name)) {
      selected.push(column);
    }
  }
  Ok(selected)
}

fn pragma_columns(conn: &Connection, table: &str) -> Result<Vec<String>, NotesError> {
  let table = quote_ident(table)?;
  let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})")).map_err(map_sql)?;
  let columns = stmt
    .query_map(params![], |row| row.get::<_, String>(1))
    .map_err(map_sql)?;
  columns.collect::<Result<Vec<_>, _>>().map_err(map_sql)
}

fn read_row(row: &Row<'_>, columns: &[String]) -> Result<EntityRow, NotesError> {
  let pk: i64 = row.get(0).map_err(map_sql)?;
  let mut values = HashMap::new();
  for (index, name) in columns.iter().enumerate().skip(1) {
    match row.get_ref(index).map_err(map_sql)? {
      ValueRef::Null => {}
      ValueRef::Integer(value) => {
        values.insert(name.clone(), SqlValue::Int(value));
      }
      ValueRef::Real(value) => {
        values.insert(name.clone(), SqlValue::Real(value));
      }
      ValueRef::Text(value) => {
        values.insert(
          name.clone(),
          SqlValue::Text(String::from_utf8_lossy(value).into_owned()),
        );
      }
      ValueRef::Blob(value) => {
        values.insert(name.clone(), SqlValue::Blob(value.to_vec()));
      }
    }
  }
  Ok(EntityRow { pk, values })
}

fn quote_ident(name: &str) -> Result<String, NotesError> {
  if name.is_empty()
    || !name
      .chars()
      .all(|character| character.is_ascii_alphanumeric() || character == '_')
  {
    return Err(NotesError::new("notes_error", "unexpected notes column name"));
  }
  Ok(format!("\"{name}\""))
}

pub(super) fn map_sql(err: rusqlite::Error) -> NotesError {
  NotesError::new("notes_error", format!("notes store query failed: {err}"))
}

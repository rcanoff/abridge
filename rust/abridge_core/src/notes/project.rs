//! JSON projections. Every listed attribute is present; missing values are null.

use serde_json::{Map, Number, Value};

use super::attributes::{self, ScalarAttr, ScalarKind};
use super::columns;
use super::decode;
use super::store::{self, EntityRow, NoteDataRow, Snapshot, SqlValue};
use super::table;
use super::timefmt;

pub(crate) fn folder(snap: &Snapshot, row: &EntityRow) -> Value {
  let mut object = object_map(scalars(row, attributes::attributes_for("ICFolder")));
  object.insert("account".to_string(), nested(snap, row, "account", "ICAccount"));
  object.insert("parent".to_string(), nested(snap, row, "parent", "ICFolder"));
  Value::Object(object)
}

pub(crate) fn note(snap: &Snapshot, row: &EntityRow) -> Value {
  let mut object = object_map(scalars(row, attributes::attributes_for("ICNote")));
  let folder_json = store::foreign_key(row, "folder")
    .and_then(|pk| store::row_by_pk(&snap.folders, pk))
    .map_or(Value::Null, |target| folder(snap, target));
  object.insert("folder".to_string(), folder_json);
  object.insert("account".to_string(), nested(snap, row, "account", "ICAccount"));
  object.insert("note_data".to_string(), note_data_json(note_data_for(snap, row)));
  object.insert("attachments".to_string(), Value::Array(attachments(snap, row.pk)));
  object.insert(
    "inline_attachments".to_string(),
    Value::Array(inline_attachments(snap, row.pk)),
  );
  Value::Object(object)
}

fn scalars(row: &EntityRow, attrs: &[ScalarAttr]) -> Value {
  let mut object = Map::new();
  for attr in attrs {
    object.insert(
      columns::snake_case(attr.name),
      scalar_json(store::non_null(row, attr.name), attr.kind),
    );
  }
  Value::Object(object)
}

fn nested(snap: &Snapshot, row: &EntityRow, relationship: &str, entity: &str) -> Value {
  let Some(pk) = store::foreign_key(row, relationship) else {
    return Value::Null;
  };
  let rows = match entity {
    "ICAccount" => &snap.accounts,
    "ICFolder" => &snap.folders,
    "ICMedia" => &snap.media,
    "ICAttachment" => &snap.attachments,
    _ => return Value::Null,
  };
  let Some(target) = store::row_by_pk(rows, pk) else {
    return Value::Null;
  };
  scalars(target, attributes::attributes_for(entity))
}

fn attachments(snap: &Snapshot, note_pk: i64) -> Vec<Value> {
  snap
    .attachments
    .iter()
    .filter(|row| store::foreign_key(row, "note") == Some(note_pk))
    .map(|row| attachment(snap, row))
    .collect()
}

pub(crate) fn attachment(snap: &Snapshot, row: &EntityRow) -> Value {
  let mut object = object_map(scalars(row, attributes::attributes_for("ICAttachment")));
  object.insert("media".to_string(), nested(snap, row, "media", "ICMedia"));
  object.insert(
    "parent_attachment".to_string(),
    nested(snap, row, "parentAttachment", "ICAttachment"),
  );
  object.insert("mergeable_data".to_string(), mergeable_json(row));
  Value::Object(object)
}

fn inline_attachments(snap: &Snapshot, note_pk: i64) -> Vec<Value> {
  snap
    .inline_attachments
    .iter()
    .filter(|row| store::foreign_key(row, "note") == Some(note_pk))
    .map(|row| {
      let mut object = object_map(scalars(row, attributes::attributes_for("ICInlineAttachment")));
      object.insert(
        "parent_attachment".to_string(),
        nested(snap, row, "parentAttachment", "ICAttachment"),
      );
      Value::Object(object)
    })
    .collect()
}

fn mergeable_json(row: &EntityRow) -> Value {
  if store::text(row, "typeUTI") != Some("com.apple.notes.table") {
    return Value::Null;
  }
  let Some(SqlValue::Blob(blob)) = store::non_null(row, "mergeableData") else {
    return Value::Null;
  };
  table::decode_mergeable(blob).unwrap_or(Value::Null)
}

fn note_data_for<'a>(snap: &'a Snapshot, note: &EntityRow) -> Option<&'a NoteDataRow> {
  let pk = store::foreign_key(note, "noteData")?;
  snap.note_data.iter().find(|row| row.pk == pk)
}

fn note_data_json(row: Option<&NoteDataRow>) -> Value {
  let Some(row) = row else {
    return Value::Null;
  };
  let data = if row.encrypted {
    Value::Null
  } else {
    row
      .data
      .as_deref()
      .and_then(decode::decode_note_blob)
      .unwrap_or(Value::Null)
  };
  serde_json::json!({ "data": data })
}

fn scalar_json(value: Option<&SqlValue>, kind: ScalarKind) -> Value {
  let Some(value) = value else {
    return Value::Null;
  };
  match kind {
    ScalarKind::Integer => match value {
      SqlValue::Int(number) => serde_json::json!(number),
      SqlValue::Real(number) => whole_i64(*number)
        .map(|number| serde_json::json!(number))
        .unwrap_or(Value::Null),
      _ => Value::Null,
    },
    ScalarKind::Double => match value {
      SqlValue::Real(number) => float_json(*number),
      SqlValue::Int(number) => serde_json::json!(number),
      _ => Value::Null,
    },
    ScalarKind::String => match value {
      SqlValue::Text(text) => Value::String(text.clone()),
      _ => Value::Null,
    },
    ScalarKind::Bool => match value {
      SqlValue::Int(0) => Value::Bool(false),
      SqlValue::Int(1) => Value::Bool(true),
      _ => Value::Null,
    },
    ScalarKind::Date => match value {
      SqlValue::Real(seconds) => date_json(*seconds),
      SqlValue::Int(seconds) => date_json(*seconds as f64),
      _ => Value::Null,
    },
  }
}

fn date_json(seconds: f64) -> Value {
  timefmt::core_data_to_rfc3339(seconds)
    .map(Value::String)
    .unwrap_or(Value::Null)
}

fn float_json(number: f64) -> Value {
  Number::from_f64(number).map(Value::Number).unwrap_or(Value::Null)
}

fn whole_i64(number: f64) -> Option<i64> {
  if !number.is_finite() || number.fract() != 0.0 {
    return None;
  }
  Some(number as i64)
}

fn object_map(value: Value) -> Map<String, Value> {
  match value {
    Value::Object(map) => map,
    _ => Map::new(),
  }
}

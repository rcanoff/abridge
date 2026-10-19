//! Reconstruct an embedded Notes table from `MergableDataProto`.

use prost::Message;
use serde_json::Value;
use std::collections::HashMap;

use super::decode::{self, topotext_json};
use super::proto_table::{MergableDataProto, MergeableDataObjectData, MergeableDataObjectEntry, ObjectId};

const RIGHT_TO_LEFT: &str = "CRTableColumnDirectionRightToLeft";
const TABLE_TYPE: &str = "com.apple.notes.ICTable";
const MAX_TABLE_CELLS: usize = 100_000;

pub(crate) fn decode_mergeable(blob: &[u8]) -> Option<Value> {
  let Some(raw) = decode::inflate(blob) else {
    tracing::debug!("table compression decode failed");
    return None;
  };
  let proto = match MergableDataProto::decode(raw.as_slice()) {
    Ok(proto) => proto,
    Err(err) => {
      tracing::debug!(error = %err, "table decode failed");
      return None;
    }
  };
  let data = proto.object.as_ref().and_then(|object| object.data.as_ref());
  let Some(data) = data else {
    tracing::debug!("table decode failed");
    return None;
  };
  match build_table(data) {
    Some(value) => Some(value),
    None => {
      tracing::debug!("table decode failed");
      None
    }
  }
}

fn build_table(data: &MergeableDataObjectData) -> Option<Value> {
  let entries = &data.entry;
  let direction = column_direction(entries, &data.key_item);
  let root = entries.iter().find(|entry| is_ic_table(entry, &data.type_item))?;
  let map = root.custom_map.as_ref()?;
  let mut rows = None;
  let mut columns = None;
  let mut cells = None;
  for item in &map.map_entry {
    let key_index = usize::try_from(item.key?).ok()?;
    let name = data.key_item.get(key_index)?;
    if !matches!(name.as_str(), "crRows" | "crColumns" | "cellColumns") {
      continue;
    }
    let target = object_index(item.value.as_ref()?)?;
    let entry = entries.get(target)?;
    match name.as_str() {
      "crRows" => rows = Some(entry),
      "crColumns" => columns = Some(entry),
      "cellColumns" => cells = Some(entry),
      _ => {}
    }
  }
  let row_positions = position_map(entries, rows?, &data.uuid_item)?;
  let column_positions = position_map(entries, columns?, &data.uuid_item)?;
  let mut grid = fill_cells(
    entries,
    cells?,
    &row_positions,
    &column_positions,
    dimension(&row_positions),
    dimension(&column_positions),
  )?;
  if direction.as_deref() == Some(RIGHT_TO_LEFT) {
    for row in &mut grid {
      row.reverse();
    }
  }
  Some(serde_json::json!({
    "table": {
      "column_direction": direction,
      "rows": grid,
    }
  }))
}

fn column_direction(entries: &[MergeableDataObjectEntry], keys: &[String]) -> Option<String> {
  let index = keys.iter().position(|key| key == "crTableColumnDirection")?;
  let target = i32::try_from(index).ok()?.checked_add(1)?;
  let mut found = None;
  for entry in entries {
    let Some(first) = entry.custom_map.as_ref().and_then(|map| map.map_entry.first()) else {
      continue;
    };
    if first.key == Some(target) {
      found = first.value.as_ref().and_then(|value| value.string_value.clone());
    }
  }
  found
}

fn is_ic_table(entry: &MergeableDataObjectEntry, types: &[String]) -> bool {
  let Some(index) = entry.custom_map.as_ref().and_then(|map| map.type_index) else {
    return false;
  };
  let Some(index) = usize::try_from(index).ok() else {
    return false;
  };
  types.get(index).map(String::as_str) == Some(TABLE_TYPE)
}

fn position_map(
  entries: &[MergeableDataObjectEntry],
  ordered: &MergeableDataObjectEntry,
  uuids: &[Vec<u8>],
) -> Option<HashMap<u64, usize>> {
  let ordering = ordered.ordered_set.as_ref()?.ordering.as_ref()?;
  let mut positions = HashMap::new();
  for (position, attachment) in ordering.array.as_ref()?.attachment.iter().enumerate() {
    let uuid_at = uuids.iter().position(|item| item == &attachment.uuid)?;
    positions.insert(uuid_at as u64, position);
  }
  if let Some(contents) = &ordering.contents {
    for element in &contents.element {
      let key_uuid = uuid_index(entries.get(object_index(element.key.as_ref()?)?)?)?;
      let value_uuid = uuid_index(entries.get(object_index(element.value.as_ref()?)?)?)?;
      let position = *positions.get(&key_uuid)?;
      positions.insert(value_uuid, position);
    }
  }
  Some(positions)
}

fn fill_cells(
  entries: &[MergeableDataObjectEntry],
  cells: &MergeableDataObjectEntry,
  row_positions: &HashMap<u64, usize>,
  column_positions: &HashMap<u64, usize>,
  row_count: usize,
  column_count: usize,
) -> Option<Vec<Vec<Value>>> {
  // Notes tables are small; malformed orderings can claim huge positions. Refuse before allocating.
  if row_count.checked_mul(column_count)? > MAX_TABLE_CELLS {
    return None;
  }
  let mut grid = vec![vec![Value::Null; column_count]; row_count];
  for column in &cells.dictionary.as_ref()?.element {
    let column_uuid = uuid_index(entries.get(object_index(column.key.as_ref()?)?)?)?;
    let column_at = *column_positions.get(&column_uuid)?;
    let row_dictionary = entries
      .get(object_index(column.value.as_ref()?)?)?
      .dictionary
      .as_ref()?;
    for row in &row_dictionary.element {
      let row_uuid = uuid_index(entries.get(object_index(row.key.as_ref()?)?)?)?;
      let row_at = *row_positions.get(&row_uuid)?;
      let cell = entries.get(object_index(row.value.as_ref()?)?)?;
      if row_at >= grid.len() || column_at >= grid[row_at].len() {
        return None;
      }
      grid[row_at][column_at] = cell.note.as_ref().map(topotext_json).unwrap_or(Value::Null);
    }
  }
  Some(grid)
}

fn dimension(positions: &HashMap<u64, usize>) -> usize {
  positions.values().copied().max().map(|index| index + 1).unwrap_or(0)
}

fn uuid_index(entry: &MergeableDataObjectEntry) -> Option<u64> {
  entry
    .custom_map
    .as_ref()?
    .map_entry
    .first()?
    .value
    .as_ref()?
    .unsigned_integer_value
}

fn object_index(id: &ObjectId) -> Option<usize> {
  usize::try_from(id.object_index?).ok()
}

#[cfg(test)]
mod tests {
  use super::{MAX_TABLE_CELLS, fill_cells};
  use crate::notes::proto_table::MergeableDataObjectEntry;
  use std::collections::HashMap;

  #[test]
  fn refuses_tables_larger_than_the_cell_limit() {
    let cells = MergeableDataObjectEntry::default();
    let empty = HashMap::new();
    assert!(fill_cells(&[], &cells, &empty, &empty, MAX_TABLE_CELLS + 1, 1).is_none());
    assert!(fill_cells(&[], &cells, &empty, &empty, usize::MAX, 2).is_none());
  }
}

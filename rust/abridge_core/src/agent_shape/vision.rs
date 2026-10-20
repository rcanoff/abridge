//! Vision text and document results.
//!
//! Swift still serializes Vision objects. [`vision_text`] and [`vision_markdown`] turn that JSON
//! into the strings agents read. Boxes and the document tree stay behind `include_geometry`.

use serde_json::{Map, Value};

use super::util;

const DROP: &[&str] = &[
  "uuid",
  "request_revision",
  "originating_request_descriptor",
  "global_segmentation_mask",
  "pixel_buffer",
  "time_range",
  "payload_data",
  "supplemental_payload_data",
  "all_points",
  "precision_estimates_per_point",
  "top_left",
  "top_right",
  "bottom_left",
  "bottom_right",
  "feature_name",
];

const MAX_DEPTH: usize = 32;

/// Lines from a `vision_recognize_text` provider payload, in reading order.
///
/// Higher Vision `y` is higher on the page. Lines on one row are joined with a space; rows with `\n`.
pub fn vision_text(raw: &Value) -> String {
  assemble_lines(text_lines(raw))
}

/// Markdown from a `vision_recognize_documents` provider payload, in document order.
pub fn vision_markdown(raw: &Value) -> String {
  let Some(results) = raw.get("results").and_then(Value::as_array) else {
    return String::new();
  };
  let mut blocks = Vec::new();
  for result in results {
    let Some(document) = result.get("document") else {
      continue;
    };
    let markdown = render_container(document, 0);
    if markdown.is_empty() {
      continue;
    }
    let (top, left) = position(document.get("bounding_region"), 0.0);
    blocks.push(Block {
      top,
      bottom: top,
      left,
      body: markdown,
      title: false,
    });
  }
  join_blocks(order_blocks(blocks))
}

pub(crate) fn shape(value: &Value) -> Value {
  util::slim_dropping(value, DROP).unwrap_or(Value::Object(Map::new()))
}

pub(crate) fn shape_text(value: &Value, include_geometry: bool) -> Value {
  let mut object = Map::new();
  let text = vision_text(value);
  if !text.is_empty() {
    object.insert("text".into(), Value::String(text));
  }
  copy_page(&mut object, value);
  if include_geometry {
    merge_geometry(&mut object, value);
  }
  Value::Object(object)
}

pub(crate) fn shape_documents(value: &Value, include_geometry: bool) -> Value {
  let mut object = Map::new();
  let markdown = vision_markdown(value);
  if !markdown.is_empty() {
    object.insert("markdown".into(), Value::String(markdown));
  }
  let detected = detected_items(value);
  if !detected.is_empty() {
    object.insert("detected".into(), Value::Array(detected));
  }
  copy_page(&mut object, value);
  if include_geometry {
    merge_geometry(&mut object, value);
  }
  Value::Object(object)
}

struct Line {
  text: String,
  left: f64,
  top: f64,
  bottom: f64,
  height: f64,
}

fn text_lines(raw: &Value) -> Vec<Line> {
  let Some(results) = raw.get("results").and_then(Value::as_array) else {
    return Vec::new();
  };
  results
    .iter()
    .enumerate()
    .filter_map(|(index, observation)| line_from_observation(observation, index))
    .collect()
}

fn line_from_observation(observation: &Value, index: usize) -> Option<Line> {
  let text = observation
    .get("candidates")?
    .as_array()?
    .first()?
    .get("string")?
    .as_str()?
    .trim();
  if text.is_empty() {
    return None;
  }
  let text = text.to_string();
  let Some(rect) = rect_of(observation.get("bounding_box")) else {
    let y = -(index as f64);
    return Some(Line {
      text,
      left: index as f64,
      top: y,
      bottom: y,
      height: 0.0,
    });
  };
  Some(Line {
    text,
    left: rect.min_x,
    top: rect.max_y,
    bottom: rect.min_y,
    height: (rect.max_y - rect.min_y).max(0.0),
  })
}

fn rect_from_box(value: &Value) -> Option<Rect> {
  let origin = value.get("origin")?;
  let size = value.get("size")?;
  let x = number(origin.get("x"))?;
  let y = number(origin.get("y"))?;
  let width = number(size.get("width")).unwrap_or(0.0);
  let height = number(size.get("height")).unwrap_or(0.0);
  Some(Rect {
    min_x: x,
    min_y: y,
    max_x: x + width,
    max_y: y + height,
  })
}

fn assemble_lines(mut lines: Vec<Line>) -> String {
  lines.sort_by(|left, right| right.top.total_cmp(&left.top).then(left.left.total_cmp(&right.left)));
  let mut rows: Vec<Vec<Line>> = Vec::new();
  for line in lines {
    let join = rows.last().is_some_and(|row| same_band(row, &line));
    if join {
      if let Some(row) = rows.last_mut() {
        row.push(line);
      }
    } else {
      rows.push(vec![line]);
    }
  }
  let mut ordered = Vec::new();
  for mut row in rows {
    row.sort_by(|left, right| left.left.total_cmp(&right.left));
    let text = row.into_iter().map(|line| line.text).collect::<Vec<_>>().join(" ");
    if !text.is_empty() {
      ordered.push(text);
    }
  }
  ordered.join("\n")
}

fn same_band(row: &[Line], line: &Line) -> bool {
  let top = row.iter().fold(f64::NEG_INFINITY, |top, item| top.max(item.top));
  let bottom = row.iter().fold(f64::INFINITY, |bottom, item| bottom.min(item.bottom));
  let overlap = top.min(line.top) - bottom.max(line.bottom);
  let min_height = row.iter().fold(line.height, |height, item| height.min(item.height));
  if min_height <= f64::EPSILON {
    let row_center = (top + bottom) / 2.0;
    let line_center = (line.top + line.bottom) / 2.0;
    return (row_center - line_center).abs() <= 0.02;
  }
  overlap >= min_height * 0.5
}

#[derive(Clone, Copy)]
struct Rect {
  min_x: f64,
  min_y: f64,
  max_x: f64,
  max_y: f64,
}

struct Block {
  top: f64,
  bottom: f64,
  left: f64,
  body: String,
  title: bool,
}

fn render_container(container: &Value, depth: usize) -> String {
  if depth > MAX_DEPTH {
    return String::new();
  }
  let occupied = occupied_boxes(container);
  let mut blocks = Vec::new();

  if let Some(title) = object_at(container, "title")
    && let Some(text) = transcript(Some(title))
  {
    let (top, bottom, left) = band(title.get("bounding_region"), f64::INFINITY);
    blocks.push(Block {
      top,
      bottom,
      left,
      body: text,
      title: true,
    });
  }

  if let Some(paragraphs) = container.get("paragraphs").and_then(Value::as_array) {
    for (index, paragraph) in paragraphs.iter().enumerate() {
      let Some(text) = transcript(Some(paragraph)) else {
        continue;
      };
      if let Some(rect) = rect_of(paragraph.get("bounding_region"))
        && occupied.iter().any(|outer| center_inside(rect, *outer))
      {
        continue;
      }
      let (top, bottom, left) = band(paragraph.get("bounding_region"), -(index as f64));
      blocks.push(Block {
        top,
        bottom,
        left,
        body: text,
        title: false,
      });
    }
  }

  if let Some(tables) = container.get("tables").and_then(Value::as_array) {
    for (index, table) in tables.iter().enumerate() {
      let body = render_table(table);
      if body.is_empty() {
        continue;
      }
      let (top, bottom, left) = band(table.get("bounding_region"), -(index as f64));
      blocks.push(Block {
        top,
        bottom,
        left,
        body,
        title: false,
      });
    }
  }

  if let Some(lists) = container.get("lists").and_then(Value::as_array) {
    for (index, list) in lists.iter().enumerate() {
      let body = render_list(list, 0, depth + 1);
      if body.is_empty() {
        continue;
      }
      let (top, bottom, left) = band(list.get("bounding_region"), -(index as f64));
      blocks.push(Block {
        top,
        bottom,
        left,
        body,
        title: false,
      });
    }
  }

  if blocks.is_empty() {
    return transcript(container.get("text")).unwrap_or_default();
  }

  let duplicated: Vec<String> = blocks
    .iter()
    .filter(|block| block.title && blocks.iter().any(|other| !other.title && other.body == block.body))
    .map(|block| block.body.clone())
    .collect();
  blocks.retain(|block| !block.title || !duplicated.contains(&block.body));
  join_blocks(order_blocks(blocks))
}

fn occupied_boxes(container: &Value) -> Vec<Rect> {
  let mut boxes = Vec::new();
  for key in ["tables", "lists"] {
    let Some(items) = container.get(key).and_then(Value::as_array) else {
      continue;
    };
    for item in items {
      if let Some(rect) = rect_of(item.get("bounding_region")) {
        boxes.push(rect);
      }
    }
  }
  boxes
}

fn render_table(table: &Value) -> String {
  let Some(rows) = table.get("rows").and_then(Value::as_array) else {
    return String::new();
  };
  let grid: Vec<Vec<String>> = rows
    .iter()
    .filter_map(|row| {
      let cells = row.as_array()?;
      let texts: Vec<String> = cells.iter().map(cell_text).collect();
      if texts.is_empty() { None } else { Some(texts) }
    })
    .collect();
  let Some(columns) = grid.iter().map(Vec::len).max().filter(|columns| *columns > 0) else {
    return String::new();
  };
  let render_row = |cells: &[String]| {
    let mut padded = cells.to_vec();
    padded.resize(columns, String::new());
    format!("| {} |", padded.join(" | "))
  };
  let mut lines = vec![
    render_row(&grid[0]),
    format!("| {} |", vec!["---"; columns].join(" | ")),
  ];
  for row in grid.iter().skip(1) {
    lines.push(render_row(row));
  }
  lines.join("\n")
}

fn cell_text(cell: &Value) -> String {
  let content = cell.get("content").unwrap_or(cell);
  escape_cell(&plain_text(content))
}

fn plain_text(container: &Value) -> String {
  let paragraphs = transcripts(container.get("paragraphs"));
  if !paragraphs.is_empty() {
    return paragraphs.join(" ");
  }
  if let Some(text) = transcript(container.get("text")) {
    return text;
  }
  transcript(container.get("title")).unwrap_or_default()
}

fn escape_cell(text: &str) -> String {
  text
    .split_whitespace()
    .collect::<Vec<_>>()
    .join(" ")
    .replace('\\', "\\\\")
    .replace('|', "\\|")
}

fn render_list(list: &Value, indent: usize, depth: usize) -> String {
  if depth > MAX_DEPTH {
    return String::new();
  }
  let Some(items) = list.get("items").and_then(Value::as_array) else {
    return String::new();
  };
  let pad = " ".repeat(indent);
  let mut lines = Vec::new();
  for (index, item) in items.iter().enumerate() {
    let marker = if ordered_marker(item.get("marker_type").and_then(Value::as_str)) {
      format!("{}. ", index + 1)
    } else {
      "- ".to_string()
    };
    let body = item_body(item);
    if !body.is_empty() {
      lines.push(format!("{pad}{marker}{body}"));
    }
    let Some(content) = item.get("content") else {
      continue;
    };
    if let Some(nested) = content.get("lists").and_then(Value::as_array) {
      for child in nested {
        let markdown = render_list(child, indent + 2, depth + 1);
        if !markdown.is_empty() {
          lines.push(markdown);
        }
      }
    }
    if let Some(tables) = content.get("tables").and_then(Value::as_array) {
      for table in tables {
        let markdown = render_table(table);
        if !markdown.is_empty() {
          lines.push(markdown);
        }
      }
    }
  }
  lines.join("\n")
}

fn ordered_marker(marker: Option<&str>) -> bool {
  matches!(
    marker,
    Some("decimal" | "decorative_decimal" | "composite_decimal" | "lowercase_latin" | "uppercase_latin")
  )
}

fn item_body(item: &Value) -> String {
  if let Some(text) = item.get("item_string").and_then(Value::as_str) {
    let trimmed = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if !trimmed.is_empty() {
      return trimmed;
    }
  }
  item.get("content").map(plain_text).unwrap_or_default()
}

fn order_blocks(mut blocks: Vec<Block>) -> Vec<Block> {
  blocks.sort_by(|left, right| right.top.total_cmp(&left.top).then(left.left.total_cmp(&right.left)));
  let mut rows: Vec<Vec<Block>> = Vec::new();
  for block in blocks {
    let join = rows.last().is_some_and(|row| blocks_same_row(row, &block));
    if join {
      if let Some(row) = rows.last_mut() {
        row.push(block);
      }
    } else {
      rows.push(vec![block]);
    }
  }
  let mut ordered = Vec::new();
  for mut row in rows {
    row.sort_by(|left, right| left.left.total_cmp(&right.left));
    ordered.extend(row);
  }
  ordered
}

fn blocks_same_row(row: &[Block], block: &Block) -> bool {
  let lines: Vec<Line> = row
    .iter()
    .map(|item| Line {
      text: String::new(),
      left: item.left,
      top: item.top,
      bottom: item.bottom,
      height: (item.top - item.bottom).max(0.0),
    })
    .collect();
  let line = Line {
    text: String::new(),
    left: block.left,
    top: block.top,
    bottom: block.bottom,
    height: (block.top - block.bottom).max(0.0),
  };
  same_band(&lines, &line)
}

fn join_blocks(blocks: Vec<Block>) -> String {
  blocks
    .into_iter()
    .map(|block| block.body)
    .filter(|body| !body.is_empty())
    .collect::<Vec<_>>()
    .join("\n\n")
}

fn detected_items(raw: &Value) -> Vec<Value> {
  let Some(results) = raw.get("results").and_then(Value::as_array) else {
    return Vec::new();
  };
  let mut detected = Vec::new();
  for result in results {
    if let Some(document) = result.get("document") {
      collect_detected(document, &mut detected, 0);
    }
  }
  detected
}

fn collect_detected(container: &Value, detected: &mut Vec<Value>, depth: usize) {
  if depth > MAX_DEPTH {
    return;
  }
  for key in ["title", "text"] {
    if let Some(node) = object_at(container, key) {
      push_detected_text(node, detected);
    }
  }
  if let Some(paragraphs) = container.get("paragraphs").and_then(Value::as_array) {
    for paragraph in paragraphs {
      push_detected_text(paragraph, detected);
    }
  }
  if let Some(tables) = container.get("tables").and_then(Value::as_array) {
    for table in tables {
      let Some(rows) = table.get("rows").and_then(Value::as_array) else {
        continue;
      };
      for row in rows {
        let Some(cells) = row.as_array() else {
          continue;
        };
        for cell in cells {
          if let Some(content) = cell.get("content") {
            collect_detected(content, detected, depth + 1);
          }
        }
      }
    }
  }
  if let Some(lists) = container.get("lists").and_then(Value::as_array) {
    for list in lists {
      let Some(items) = list.get("items").and_then(Value::as_array) else {
        continue;
      };
      for item in items {
        if let Some(content) = item.get("content") {
          collect_detected(content, detected, depth + 1);
        }
      }
    }
  }
  if let Some(barcodes) = container.get("barcodes").and_then(Value::as_array) {
    for barcode in barcodes {
      if let Some(item) = barcode_detected(barcode) {
        push_unique(detected, item);
      }
    }
  }
}

fn push_detected_text(node: &Value, detected: &mut Vec<Value>) {
  let Some(items) = node.get("detected_data").and_then(Value::as_array) else {
    return;
  };
  for item in items {
    let Some(details) = item.get("match").and_then(|match_| match_.get("details")) else {
      continue;
    };
    if let Some(slimmed) = util::slim(details) {
      push_unique(detected, slimmed);
    }
  }
}

fn barcode_detected(barcode: &Value) -> Option<Value> {
  let mut object = Map::new();
  object.insert("type".into(), Value::String("barcode".into()));
  if let Some(symbology) = barcode
    .get("symbology")
    .and_then(Value::as_str)
    .filter(|text| !text.is_empty())
  {
    object.insert("symbology".into(), Value::String(symbology.to_string()));
  }
  if let Some(payload) = barcode
    .get("payload_string")
    .and_then(Value::as_str)
    .filter(|text| !text.is_empty())
  {
    object.insert("payload_string".into(), Value::String(payload.to_string()));
  }
  if object.len() == 1 {
    None
  } else {
    Some(Value::Object(object))
  }
}

fn push_unique(detected: &mut Vec<Value>, item: Value) {
  if !detected.contains(&item) {
    detected.push(item);
  }
}

fn copy_page(object: &mut Map<String, Value>, value: &Value) {
  util::copy_number(object, value, "page");
  util::copy_number(object, value, "page_count");
}

fn merge_geometry(object: &mut Map<String, Value>, value: &Value) {
  let Some(Value::Object(slimmed)) = util::slim_dropping(value, DROP) else {
    return;
  };
  for (key, item) in slimmed {
    object.entry(key).or_insert(item);
  }
}

fn object_at<'a>(value: &'a Value, key: &str) -> Option<&'a Value> {
  value.get(key).filter(|item| item.is_object())
}

fn transcript(node: Option<&Value>) -> Option<String> {
  let text = node?.get("transcript")?.as_str()?.trim();
  if text.is_empty() { None } else { Some(text.to_string()) }
}

fn transcripts(nodes: Option<&Value>) -> Vec<String> {
  nodes
    .and_then(Value::as_array)
    .map(|items| items.iter().filter_map(|item| transcript(Some(item))).collect())
    .unwrap_or_default()
}

fn position(region: Option<&Value>, fallback_top: f64) -> (f64, f64) {
  rect_of(region)
    .map(|rect| (rect.max_y, rect.min_x))
    .unwrap_or((fallback_top, 0.0))
}

fn band(region: Option<&Value>, fallback_top: f64) -> (f64, f64, f64) {
  rect_of(region)
    .map(|rect| (rect.max_y, rect.min_y, rect.min_x))
    .unwrap_or((fallback_top, fallback_top, 0.0))
}

fn rect_of(region: Option<&Value>) -> Option<Rect> {
  let region = region?;
  if let Some(points) = region.get("normalized_points").and_then(Value::as_array) {
    return rect_from_points(points);
  }
  rect_from_box(region)
}

fn rect_from_points(points: &[Value]) -> Option<Rect> {
  let mut rect: Option<Rect> = None;
  for point in points {
    let x = number(point.get("x"))?;
    let y = number(point.get("y"))?;
    rect = Some(match rect {
      Some(rect) => Rect {
        min_x: rect.min_x.min(x),
        min_y: rect.min_y.min(y),
        max_x: rect.max_x.max(x),
        max_y: rect.max_y.max(y),
      },
      None => Rect {
        min_x: x,
        min_y: y,
        max_x: x,
        max_y: y,
      },
    });
  }
  rect
}

fn center_inside(inner: Rect, outer: Rect) -> bool {
  let x = (inner.min_x + inner.max_x) / 2.0;
  let y = (inner.min_y + inner.max_y) / 2.0;
  x >= outer.min_x && x <= outer.max_x && y >= outer.min_y && y <= outer.max_y
}

fn number(value: Option<&Value>) -> Option<f64> {
  value.and_then(Value::as_f64)
}

#[cfg(test)]
mod tests {
  use super::{shape_documents, shape_text, vision_markdown, vision_text};
  use serde_json::{Value, json};

  fn line(text: &str, x: f64, y: f64, width: f64, height: f64) -> Value {
    json!({
      "uuid": format!("uuid-{text}"),
      "confidence": 0.95,
      "time_range": { "start_seconds": 0, "duration_seconds": 0 },
      "request_revision": 3,
      "bounding_box": {
        "origin": { "x": x, "y": y },
        "size": { "width": width, "height": height }
      },
      "top_left": { "x": x, "y": y + height },
      "top_right": { "x": x + width, "y": y + height },
      "bottom_left": { "x": x, "y": y },
      "bottom_right": { "x": x + width, "y": y },
      "candidates": [
        { "string": text, "confidence": 0.95, "request_revision": 3 },
        { "string": format!("{text}?"), "confidence": 0.2, "request_revision": 3 }
      ]
    })
  }

  #[test]
  fn text_reads_two_columns_top_to_bottom() {
    let raw = json!({
      "results": [
        line("Right bottom", 0.55, 0.39, 0.3, 0.05),
        line("Left top", 0.05, 0.80, 0.3, 0.06),
        line("Right top", 0.60, 0.81, 0.3, 0.05),
        line("Left bottom", 0.05, 0.40, 0.3, 0.06)
      ],
      "page": 2,
      "page_count": 4
    });
    assert_eq!(vision_text(&raw), "Left top Right top\nLeft bottom Right bottom");
    let shaped = shape_text(&raw, false);
    assert_eq!(shaped["text"], "Left top Right top\nLeft bottom Right bottom");
    assert_eq!(shaped["page"], 2);
    assert_eq!(shaped["page_count"], 4);
    assert!(shaped.get("results").is_none());

    let detailed = shape_text(&raw, true);
    assert_eq!(detailed["text"], shaped["text"]);
    assert_eq!(detailed["results"][0]["candidates"][0]["string"], "Right bottom");
    assert!(detailed["results"][0].get("uuid").is_none());
    assert!(detailed["results"][0].get("top_left").is_none());
    assert!(detailed["results"][0].get("bounding_box").is_some());
  }

  #[test]
  fn receipt_text_drops_line_geometry() {
    let lines = [
      "MARKET",
      "Milk 2.00",
      "Eggs 3.50",
      "Bread 1.25",
      "Total 6.75",
      "Thank you",
      "Card 4242",
      "Date 2026",
    ];
    let results: Vec<Value> = lines
      .iter()
      .enumerate()
      .map(|(index, text)| {
        let mut observation = line(text, 0.08, 0.90 - index as f64 * 0.08, 0.7, 0.05);
        observation["global_segmentation_mask"] = json!({
          "pixel_buffer": { "data": "A".repeat(500), "width": 8, "height": 8 }
        });
        observation
      })
      .collect();
    let raw = json!({ "results": results });
    let before = super::shape(&raw).to_string();
    let after = shape_text(&raw, false).to_string();
    assert_eq!(
      shape_text(&raw, false)["text"],
      "MARKET\nMilk 2.00\nEggs 3.50\nBread 1.25\nTotal 6.75\nThank you\nCard 4242\nDate 2026"
    );
    assert!(
      after.len() * 4 < before.len(),
      "receipt text before {} after {}",
      before.len(),
      after.len()
    );
    println!("receipt text before {} after {}", before.len(), after.len());
  }

  fn region(min_x: f64, min_y: f64, max_x: f64, max_y: f64) -> Value {
    let mut points = vec![
      json!({ "x": min_x, "y": min_y }),
      json!({ "x": max_x, "y": min_y }),
      json!({ "x": max_x, "y": max_y }),
      json!({ "x": min_x, "y": max_y }),
    ];
    for index in 0..80 {
      let t = index as f64 / 80.0;
      let fraction = 0.2 + (index % 5) as f64 * 0.12;
      points.push(json!({
        "x": min_x + (max_x - min_x) * t,
        "y": min_y + (max_y - min_y) * fraction
      }));
    }
    json!({
      "aspect_ratio": 1.0,
      "index_path": [0],
      "point_count": points.len(),
      "normalized_points": points,
      "child_contours": []
    })
  }

  fn text_node(transcript: &str, region: Value, detected: Value) -> Value {
    json!({
      "transcript": transcript,
      "text_alignment": "leading",
      "detected_data": detected,
      "lines": [{
        "uuid": format!("line-{transcript}"),
        "confidence": 0.99,
        "transcript": transcript,
        "bounding_region": region,
        "candidates": [{ "string": transcript, "confidence": 0.99 }],
        "top_left": { "x": 0.0, "y": 1.0 },
        "top_right": { "x": 1.0, "y": 1.0 },
        "bottom_left": { "x": 0.0, "y": 0.0 },
        "bottom_right": { "x": 1.0, "y": 0.0 }
      }],
      "words": null,
      "bounding_region": region
    })
  }

  fn cell(transcript: &str) -> Value {
    json!({
      "content": {
        "title": null,
        "text": text_node(transcript, region(0.0, 0.0, 0.1, 0.1), json!([])),
        "paragraphs": [],
        "tables": [],
        "lists": [],
        "barcodes": [],
        "bounding_region": region(0.0, 0.0, 0.1, 0.1)
      },
      "row_range": { "lower": 0, "upper": 0 },
      "column_range": { "lower": 0, "upper": 0 }
    })
  }

  fn phone(number: &str) -> Value {
    json!([{
      "match": {
        "range": { "location": 0, "length": 8 },
        "preferred_highlight_style": "regular",
        "details": { "type": "phone_number", "phone_number": number, "label": null }
      },
      "bounding_region": region(0.1, 0.1, 0.2, 0.2)
    }])
  }

  #[test]
  fn markdown_orders_paragraphs_table_and_list() {
    let page = json!({
      "title": text_node("Receipt", region(0.1, 0.92, 0.4, 0.97), json!([])),
      "text": text_node("FULL PAGE DUMP", region(0.0, 0.0, 1.0, 1.0), json!([])),
      "paragraphs": [
        text_node("See you tomorrow.", region(0.1, 0.16, 0.8, 0.24), json!([])),
        text_node("INSIDE TABLE", region(0.2, 0.66, 0.4, 0.72), json!([])),
        text_node("Opened the market early.", region(0.1, 0.82, 0.8, 0.88), phone("555-0100")),
        text_node("Closed after lunch.", region(0.1, 0.50, 0.8, 0.56), json!([]))
      ],
      "tables": [{
        "rows": [
          [cell("Item"), cell("Qty")],
          [cell("Milk"), cell("2")],
          [cell("a|b"), cell("1")]
        ],
        "columns": [],
        "bounding_region": region(0.1, 0.62, 0.9, 0.78)
      }],
      "lists": [{
        "items": [
          {
            "content": empty_container(),
            "marker_type": "bullet",
            "marker_string": "•",
            "item_string": "Eggs"
          },
          {
            "content": {
              "title": null,
              "text": text_node("Bread", region(0.12, 0.32, 0.4, 0.36), json!([])),
              "paragraphs": [],
              "tables": [],
              "lists": [{
                "items": [{
                  "content": empty_container(),
                  "marker_type": "hyphen",
                  "marker_string": "-",
                  "item_string": "Sourdough"
                }],
                "bounding_region": region(0.16, 0.30, 0.5, 0.34)
              }],
              "barcodes": [],
              "bounding_region": region(0.12, 0.30, 0.5, 0.38)
            },
            "marker_type": "bullet",
            "marker_string": "•",
            "item_string": "Bread"
          },
        ],
        "bounding_region": region(0.1, 0.28, 0.7, 0.46)
      }],
      "barcodes": [{
        "symbology": "qr",
        "payload_string": "https://example.com/receipt",
        "bounding_region": region(0.7, 0.02, 0.95, 0.12),
        "top_left": { "x": 0.7, "y": 0.12 }
      }],
      "bounding_region": region(0.0, 0.0, 1.0, 1.0)
    });
    let raw = json!({
      "results": [{
        "uuid": "doc-1",
        "confidence": 0.9,
        "document": page
      }],
      "segmentation": { "global_segmentation_mask": { "pixel_buffer": { "data": "B".repeat(2000) } } },
      "page": 1,
      "page_count": 3
    });
    let markdown = vision_markdown(&raw);
    assert_eq!(
      markdown,
      "\
Receipt

Opened the market early.

| Item | Qty |
| --- | --- |
| Milk | 2 |
| a\\|b | 1 |

Closed after lunch.

- Eggs
- Bread
  - Sourdough

See you tomorrow."
    );
    assert!(!markdown.contains("FULL PAGE DUMP"));
    assert!(!markdown.contains("INSIDE TABLE"));

    let shaped = shape_documents(&raw, false);
    assert_eq!(shaped["markdown"], markdown);
    assert_eq!(shaped["page"], 1);
    assert_eq!(shaped["page_count"], 3);
    assert!(shaped.get("results").is_none());
    assert!(shaped.get("segmentation").is_none());
    assert_eq!(shaped["detected"][0]["type"], "phone_number");
    assert_eq!(shaped["detected"][0]["phone_number"], "555-0100");
    assert!(shaped["detected"][0].get("label").is_none());
    assert_eq!(shaped["detected"][1]["type"], "barcode");
    assert_eq!(shaped["detected"][1]["symbology"], "qr");
    assert_eq!(shaped["detected"][1]["payload_string"], "https://example.com/receipt");

    let before = super::shape(&raw).to_string();
    let after = shaped.to_string();
    assert!(
      after.len() * 4 < before.len(),
      "document before {} after {}",
      before.len(),
      after.len()
    );
    println!("document before {} after {}", before.len(), after.len());

    let detailed = shape_documents(&raw, true);
    assert_eq!(detailed["markdown"], markdown);
    assert!(detailed.get("results").is_some());
    assert!(detailed["results"][0].get("uuid").is_none());
    assert!(detailed.get("segmentation").is_none());
  }

  #[test]
  fn markdown_numbers_a_decimal_list_and_falls_back_to_text() {
    let raw = json!({
      "results": [{
        "document": {
          "title": null,
          "text": text_node("Only the transcript.", region(0.1, 0.2, 0.8, 0.4), json!([])),
          "paragraphs": [],
          "tables": [],
          "lists": [],
          "barcodes": [],
          "bounding_region": region(0.0, 0.0, 1.0, 1.0)
        }
      }]
    });
    assert_eq!(vision_markdown(&raw), "Only the transcript.");

    let listed = json!({
      "results": [{
        "document": {
          "title": null,
          "text": text_node("ignored", region(0.0, 0.0, 1.0, 1.0), json!([])),
          "paragraphs": [],
          "tables": [],
          "lists": [{
            "items": [
              { "content": empty_container(), "marker_type": "lowercase_latin", "marker_string": "a.", "item_string": "Alpha" },
              { "content": empty_container(), "marker_type": "lowercase_latin", "marker_string": "b.", "item_string": "Beta" }
            ],
            "bounding_region": region(0.1, 0.2, 0.6, 0.5)
          }],
          "barcodes": [],
          "bounding_region": region(0.0, 0.0, 1.0, 1.0)
        }
      }]
    });
    assert_eq!(vision_markdown(&listed), "1. Alpha\n2. Beta");
  }

  fn empty_container() -> Value {
    json!({
      "title": null,
      "text": text_node("", region(0.0, 0.0, 0.01, 0.01), json!([])),
      "paragraphs": [],
      "tables": [],
      "lists": [],
      "barcodes": [],
      "bounding_region": region(0.0, 0.0, 0.01, 0.01)
    })
  }
}

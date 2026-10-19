//! Markdown for an agent reading a note. Paragraph styles follow apple_cloud_notes_parser
//! (`STYLE_TYPE_*` / `style_enum`, font formatting on attribute-run field 5).

use prost::Message;
use serde_json::Value;
use std::collections::{HashMap, HashSet};

use super::decode;
use super::proto_note::{AttachmentInfo, AttributeRun, NoteDocument};
use super::store::{self, EntityRow, Snapshot, SqlValue};
use super::table;

const STYLE_TITLE: i32 = 0;
const STYLE_HEADING: i32 = 1;
const STYLE_SUBHEADING: i32 = 2;
const STYLE_MONOSPACED: i32 = 4;
const STYLE_DOTTED: i32 = 100;
const STYLE_DASHED: i32 = 101;
const STYLE_NUMBERED: i32 = 102;
const STYLE_CHECKLIST: i32 = 103;

const TABLE_UTI: &str = "com.apple.notes.table";
const GALLERY_UTI: &str = "com.apple.notes.gallery";

/// Whether the body can be inspected. False when it is absent, encrypted, past the inflate limit,
/// or not a note protobuf — the same cases where a decoded attachment list would be empty for a
/// reason other than "this note has no attachments."
pub(crate) fn body_is_available(snap: &Snapshot, note: &EntityRow) -> bool {
  decode_body(snap, note).is_some()
}

/// Attachment identifiers named by the body's attribute runs. Empty when the body is absent,
/// encrypted, or undecodable, so a note lists no attachments it does not still reference.
pub(crate) fn referenced_attachment_identifiers(snap: &Snapshot, note: &EntityRow) -> HashSet<String> {
  let Some(text) = decode_body(snap, note) else {
    return HashSet::new();
  };
  text
    .attribute_run
    .iter()
    .filter_map(|run| {
      run
        .attachment_info
        .as_ref()
        .and_then(|info| info.attachment_identifier.as_ref())
        .filter(|identifier| !identifier.is_empty())
        .cloned()
    })
    .collect()
}

/// The note body as Markdown. `None` when the body is absent, encrypted, or undecodable.
pub(crate) fn note_markdown(snap: &Snapshot, note: &EntityRow) -> Option<String> {
  let text = decode_body(snap, note)?;
  let source = text.string.as_deref().unwrap_or("");
  let mut markdown = render(snap, source, &text.attribute_run);
  markdown.retain(|character| character != '\u{FFFC}');
  Some(markdown)
}

fn decode_body(snap: &Snapshot, note: &EntityRow) -> Option<super::proto_note::TopotextString> {
  let pk = store::foreign_key(note, "noteData")?;
  let row = snap.note_data.iter().find(|row| row.pk == pk)?;
  if row.encrypted {
    return None;
  }
  let blob = row.data.as_deref()?;
  let Some(raw) = decode::inflate(blob) else {
    tracing::debug!("note body compression decode failed");
    return None;
  };
  let document = match NoteDocument::decode(raw.as_slice()) {
    Ok(document) => document,
    Err(err) => {
      tracing::debug!(error = %err, "note body decode failed");
      return None;
    }
  };
  let Some(text) = document.version.and_then(|version| version.data) else {
    tracing::debug!("note body decode produced no text");
    return None;
  };
  Some(text)
}

struct Line<'a> {
  style: i32,
  indent: i32,
  quote: i32,
  done: Option<bool>,
  styled: bool,
  spans: Vec<Span<'a>>,
}

enum Span<'a> {
  Text(TextSpan<'a>),
  Embed(String),
}

struct TextSpan<'a> {
  text: &'a str,
  weight: i32,
  point_size: Option<f32>,
  strike: bool,
  link: Option<&'a str>,
}

#[derive(Clone, Copy)]
struct Para {
  style: i32,
  indent: i32,
  quote: i32,
  done: Option<bool>,
}

impl Default for Line<'_> {
  fn default() -> Self {
    Self {
      style: -1,
      indent: 0,
      quote: 0,
      done: None,
      styled: false,
      spans: Vec::new(),
    }
  }
}

fn render(snap: &Snapshot, source: &str, runs: &[AttributeRun]) -> String {
  let lines = lines_of(snap, source, runs);
  let mut blocks = Vec::new();
  let mut numbers = HashMap::new();
  let mut index = 0;
  while index < lines.len() {
    if code_quote(&lines[index]).is_some() {
      let quote = lines[index].quote;
      let start = index;
      index += 1;
      while index < lines.len() && code_quote(&lines[index]) == Some(quote) {
        index += 1;
      }
      numbers.clear();
      let body = lines[start..index]
        .iter()
        .map(plain_text)
        .collect::<Vec<_>>()
        .join("\n");
      blocks.push(prefix_quote(&fenced(&body), quote));
    } else {
      blocks.push(render_paragraph(&lines[index], &mut numbers));
      index += 1;
    }
  }
  blocks.join("\n")
}

fn lines_of<'a>(snap: &Snapshot, source: &'a str, runs: &'a [AttributeRun]) -> Vec<Line<'a>> {
  let mut lines = Vec::new();
  let mut line = Line::default();
  let mut seen_files = HashSet::new();
  let mut rest = source;
  for run in runs {
    let len = usize::try_from(run.length.unwrap_or(0).max(0)).unwrap_or(usize::MAX);
    let (chunk, tail) = take_utf16(rest, len);
    push_run(snap, &mut line, &mut lines, run, chunk, &mut seen_files);
    rest = tail;
    if rest.is_empty() {
      break;
    }
  }
  if !rest.is_empty() {
    push_plain(&mut line, &mut lines, rest);
  }
  if line.styled || !line.spans.is_empty() {
    lines.push(line);
  }
  lines
}

/// Attribute-run lengths are UTF-16 code units (Notes stores `NSString` lengths).
fn take_utf16(text: &str, len: usize) -> (&str, &str) {
  if len == 0 {
    return ("", text);
  }
  let mut units = 0;
  for (index, character) in text.char_indices() {
    let width = character.len_utf16();
    if units + width > len {
      return (&text[..index], &text[index..]);
    }
    units += width;
    if units == len {
      let next = index + character.len_utf8();
      return (&text[..next], &text[next..]);
    }
  }
  (text, "")
}

fn push_run<'a>(
  snap: &Snapshot,
  line: &mut Line<'a>,
  lines: &mut Vec<Line<'a>>,
  run: &'a AttributeRun,
  mut rest: &'a str,
  seen_files: &mut HashSet<&'a str>,
) {
  let para = paragraph_of(run);
  while !rest.is_empty() {
    if let Some(stripped) = rest.strip_prefix('\n') {
      if !line.styled {
        apply_style(line, para);
      }
      lines.push(std::mem::take(line));
      rest = stripped;
      continue;
    }
    apply_style(line, para);
    if let Some(stripped) = rest.strip_prefix('\u{FFFC}') {
      let file_id = file_attachment_id(snap, run.attachment_info.as_ref());
      if file_id.is_some_and(|identifier| !seen_files.insert(identifier)) {
        rest = stripped;
        continue;
      }
      let embed = embed_for(snap, run.attachment_info.as_ref());
      match line.spans.last() {
        // Adjacent identical embeds (a repeated hashtag placeholder) show once.
        Some(Span::Embed(previous)) if *previous == embed => {}
        Some(Span::Embed(_)) => {
          line.spans.push(Span::Text(TextSpan {
            text: " ",
            weight: 0,
            point_size: None,
            strike: false,
            link: None,
          }));
          line.spans.push(Span::Embed(embed));
        }
        _ => line.spans.push(Span::Embed(embed)),
      }
      rest = stripped;
      continue;
    }
    let end = rest.find(['\n', '\u{FFFC}']).unwrap_or(rest.len());
    let (mut chunk, tail) = rest.split_at(end);
    if let Some(stripped) = chunk.strip_suffix('\r') {
      chunk = stripped;
    }
    if !chunk.is_empty() {
      line.spans.push(Span::Text(TextSpan {
        text: chunk,
        weight: run.font_weight.unwrap_or(0),
        point_size: run.font.as_ref().and_then(|font| font.point_size),
        strike: run.strikethrough.unwrap_or(0) != 0,
        link: run.link.as_deref().filter(|link| !link.is_empty()),
      }));
    }
    rest = tail;
  }
}

fn push_plain<'a>(line: &mut Line<'a>, lines: &mut Vec<Line<'a>>, mut rest: &'a str) {
  while !rest.is_empty() {
    if let Some(stripped) = rest.strip_prefix('\n') {
      lines.push(std::mem::take(line));
      rest = stripped;
      continue;
    }
    if let Some(stripped) = rest.strip_prefix('\u{FFFC}') {
      line.spans.push(Span::Embed(String::new()));
      rest = stripped;
      continue;
    }
    let end = rest.find(['\n', '\u{FFFC}']).unwrap_or(rest.len());
    let (mut chunk, tail) = rest.split_at(end);
    if let Some(stripped) = chunk.strip_suffix('\r') {
      chunk = stripped;
    }
    if !chunk.is_empty() {
      line.spans.push(Span::Text(TextSpan {
        text: chunk,
        weight: 0,
        point_size: None,
        strike: false,
        link: None,
      }));
    }
    rest = tail;
  }
}

fn paragraph_of(run: &AttributeRun) -> Option<Para> {
  let style = run.paragraph_style.as_ref()?;
  Some(Para {
    style: style.style.unwrap_or(-1),
    indent: style.indent.unwrap_or(0),
    quote: style.block_quote_level.unwrap_or(0),
    done: style.todo.as_ref().and_then(|todo| todo.done),
  })
}

fn apply_style(line: &mut Line<'_>, para: Option<Para>) {
  if line.styled {
    return;
  }
  let Some(para) = para else {
    return;
  };
  line.style = para.style;
  line.indent = para.indent;
  line.quote = para.quote;
  line.done = para.done;
  line.styled = true;
}

fn code_quote(line: &Line<'_>) -> Option<i32> {
  if line.style == STYLE_MONOSPACED && !line.spans.iter().any(|span| matches!(span, Span::Embed(_))) {
    Some(line.quote)
  } else {
    None
  }
}

fn plain_text(line: &Line<'_>) -> String {
  let mut out = String::new();
  for span in &line.spans {
    if let Span::Text(text) = span {
      out.push_str(text.text);
    }
  }
  out
}

fn render_paragraph(line: &Line<'_>, numbers: &mut HashMap<i32, i32>) -> String {
  if is_bare_block(line) {
    numbers.clear();
    return render_spans(&line.spans, false);
  }
  let marker = list_marker(line, numbers);
  let from_font = font_heading(line);
  let heading = if from_font.is_empty() {
    heading_prefix(line.style)
  } else {
    from_font
  };
  let indent = if marker.is_empty() {
    String::new()
  } else {
    "  ".repeat(clamped(line.indent))
  };
  let body = render_spans(&line.spans, !from_font.is_empty());
  prefix_quote(&format!("{indent}{marker}{heading}{body}"), line.quote)
}

/// A written `#` / `##` is stored as bold 24pt / 18pt with no paragraph style. Render that back as
/// a heading, and leave the bold marks off because the size was the heading.
fn font_heading(line: &Line<'_>) -> &'static str {
  if !plain_paragraph(line) {
    return "";
  }
  let mut min_size: Option<f32> = None;
  let mut saw_text = false;
  for span in &line.spans {
    match span {
      Span::Embed(_) => return "",
      Span::Text(text) => {
        if text.text.chars().all(char::is_whitespace) {
          continue;
        }
        if normalize_weight(text.weight) != 1 {
          return "";
        }
        let Some(size) = text.point_size else {
          return "";
        };
        saw_text = true;
        min_size = Some(min_size.map_or(size, |current| current.min(size)));
      }
    }
  }
  if !saw_text {
    return "";
  }
  match min_size {
    Some(size) if size >= 24.0 => "# ",
    Some(size) if size >= 18.0 => "## ",
    _ => "",
  }
}

fn plain_paragraph(line: &Line<'_>) -> bool {
  line.quote == 0
    && line.indent == 0
    && line.done.is_none()
    && !matches!(
      line.style,
      STYLE_TITLE
        | STYLE_HEADING
        | STYLE_SUBHEADING
        | STYLE_MONOSPACED
        | STYLE_DOTTED
        | STYLE_DASHED
        | STYLE_NUMBERED
        | STYLE_CHECKLIST
    )
}

fn is_bare_block(line: &Line<'_>) -> bool {
  matches!(&line.spans[..], [Span::Embed(text)] if text.contains('\n'))
}

fn list_marker(line: &Line<'_>, numbers: &mut HashMap<i32, i32>) -> String {
  match line.style {
    STYLE_DOTTED | STYLE_DASHED => {
      numbers.clear();
      "- ".to_string()
    }
    STYLE_NUMBERED => {
      numbers.retain(|indent, _| *indent <= line.indent);
      let next = numbers.entry(line.indent).or_insert(0);
      *next += 1;
      format!("{next}. ")
    }
    STYLE_CHECKLIST => {
      numbers.clear();
      if line.done == Some(true) {
        "- [x] ".to_string()
      } else {
        "- [ ] ".to_string()
      }
    }
    _ => {
      numbers.clear();
      String::new()
    }
  }
}

fn heading_prefix(style: i32) -> &'static str {
  match style {
    STYLE_TITLE => "# ",
    STYLE_HEADING => "## ",
    STYLE_SUBHEADING => "### ",
    _ => "",
  }
}

fn render_spans(spans: &[Span<'_>], suppress_bold: bool) -> String {
  let mut out = String::new();
  let mut index = 0;
  while index < spans.len() {
    match &spans[index] {
      Span::Embed(embed) => {
        if embed.contains('\n') && !out.is_empty() && !out.ends_with('\n') {
          out.push('\n');
        }
        out.push_str(embed);
        index += 1;
      }
      Span::Text(text) => {
        let weight = if suppress_bold {
          0
        } else {
          normalize_weight(text.weight)
        };
        let key = (weight, text.strike, text.link);
        let mut combined = String::new();
        while index < spans.len() {
          if let Span::Text(next) = &spans[index] {
            let next_weight = if suppress_bold {
              0
            } else {
              normalize_weight(next.weight)
            };
            if (next_weight, next.strike, next.link) == key {
              combined.push_str(next.text);
              index += 1;
              continue;
            }
          }
          break;
        }
        out.push_str(&wrap(&combined, key));
      }
    }
  }
  out
}

fn normalize_weight(weight: i32) -> i32 {
  match weight {
    1..=3 => weight,
    _ => 0,
  }
}

fn wrap(text: &str, key: (i32, bool, Option<&str>)) -> String {
  if text.is_empty() {
    return String::new();
  }
  let mut body = escape_text(text);
  let marker = match key.0 {
    1 => "**",
    2 => "*",
    3 => "***",
    _ => "",
  };
  if !marker.is_empty() {
    body = format!("{marker}{body}{marker}");
  }
  if key.1 {
    body = format!("~~{body}~~");
  }
  if let Some(url) = key.2 {
    body = format!("[{body}]({})", escape_url(url));
  }
  body
}

fn fenced(body: &str) -> String {
  let mut width = 3;
  while body.contains(&"`".repeat(width)) {
    width += 1;
  }
  let marker = "`".repeat(width);
  format!("{marker}\n{body}\n{marker}")
}

fn prefix_quote(text: &str, level: i32) -> String {
  let level = clamped(level);
  if level == 0 || text.is_empty() {
    return text.to_string();
  }
  let prefix = "> ".repeat(level);
  text
    .split('\n')
    .map(|line| format!("{prefix}{line}"))
    .collect::<Vec<_>>()
    .join("\n")
}

fn clamped(value: i32) -> usize {
  usize::try_from(value).unwrap_or(0).min(8)
}

/// A file, table, or gallery placeholder. Inline hashtags and mentions are text, so a repeated
/// tag stays. Notes' scripting attach stores two placeholders for one file, adjacent or interleaved.
fn file_attachment_id<'a>(snap: &Snapshot, info: Option<&'a AttachmentInfo>) -> Option<&'a str> {
  let identifier = info?
    .attachment_identifier
    .as_deref()
    .filter(|identifier| !identifier.is_empty())?;
  if find_by_id(&snap.inline_attachments, identifier).is_some() {
    return None;
  }
  Some(identifier)
}

fn embed_for(snap: &Snapshot, info: Option<&AttachmentInfo>) -> String {
  let Some(info) = info else {
    return String::new();
  };
  let identifier = info.attachment_identifier.as_deref().unwrap_or("");
  if let Some(inline) = find_by_id(&snap.inline_attachments, identifier) {
    return escape_text(store::text(inline, "altText").unwrap_or(""));
  }
  if let Some(attachment) = find_by_id(&snap.attachments, identifier) {
    return attachment_embed(snap, attachment, info, identifier);
  }
  let label = info
    .type_uti
    .as_deref()
    .filter(|uti| !uti.is_empty())
    .unwrap_or("attachment");
  if identifier.is_empty() {
    return escape_label(label);
  }
  attachment_link(&escape_label(label), identifier)
}

fn attachment_embed(snap: &Snapshot, row: &EntityRow, info: &AttachmentInfo, identifier: &str) -> String {
  let uti = info.type_uti.as_deref();
  if is_type(row, uti, TABLE_UTI)
    && let Some(table) = table_markdown(row)
  {
    return table;
  }
  if is_type(row, uti, GALLERY_UTI) {
    let label = match store::text(row, "title").filter(|title| !title.is_empty()) {
      Some(title) => format!("Gallery: {}", escape_label(title)),
      None => "Gallery".to_string(),
    };
    return attachment_link(&label, identifier);
  }
  let label = store::text(row, "title")
    .filter(|title| !title.is_empty())
    .or_else(|| file_name(snap, row))
    .or_else(|| store::text(row, "typeUTI").filter(|uti| !uti.is_empty()))
    .or_else(|| uti.filter(|value| !value.is_empty()))
    .unwrap_or("attachment");
  attachment_link(&escape_label(label), identifier)
}

fn is_type(row: &EntityRow, run_uti: Option<&str>, expected: &str) -> bool {
  store::text(row, "typeUTI") == Some(expected) || run_uti == Some(expected)
}

fn find_by_id<'a>(rows: &'a [EntityRow], identifier: &str) -> Option<&'a EntityRow> {
  if identifier.is_empty() {
    return None;
  }
  rows
    .iter()
    .find(|row| store::text(row, "identifier") == Some(identifier))
}

fn file_name<'a>(snap: &'a Snapshot, row: &EntityRow) -> Option<&'a str> {
  let media = store::row_by_pk(&snap.media, store::foreign_key(row, "media")?)?;
  store::text(media, "filename").filter(|name| !name.is_empty())
}

pub(crate) fn table_markdown(row: &EntityRow) -> Option<String> {
  let blob = match store::non_null(row, "mergeableData")? {
    SqlValue::Blob(blob) => blob.as_slice(),
    _ => return None,
  };
  let decoded = table::decode_mergeable(blob)?;
  let rows = decoded.pointer("/table/rows")?.as_array()?;
  let grid: Vec<Vec<String>> = rows
    .iter()
    .map(|row| {
      row
        .as_array()
        .map(|cells| cells.iter().map(cell_text).collect())
        .unwrap_or_default()
    })
    .collect();
  render_table(&grid)
}

fn cell_text(cell: &Value) -> String {
  escape_cell(cell.get("string").and_then(Value::as_str).unwrap_or(""))
}

fn render_table(grid: &[Vec<String>]) -> Option<String> {
  if grid.is_empty() {
    return None;
  }
  let width = grid.iter().map(Vec::len).max().unwrap_or(0);
  if width == 0 {
    return None;
  }
  let mut lines = Vec::with_capacity(grid.len() + 1);
  lines.push(format_row(&pad(&grid[0], width)));
  lines.push(format!("| {} |", vec!["---"; width].join(" | ")));
  for row in grid.iter().skip(1) {
    lines.push(format_row(&pad(row, width)));
  }
  Some(lines.join("\n"))
}

fn pad(row: &[String], width: usize) -> Vec<String> {
  let mut cells = row.to_vec();
  cells.resize(width, String::new());
  cells
}

fn format_row(cells: &[String]) -> String {
  format!("| {} |", cells.join(" | "))
}

fn attachment_link(label: &str, identifier: &str) -> String {
  format!("[{label}](attachment:{identifier})")
}

fn escape_text(text: &str) -> String {
  let mut out = String::with_capacity(text.len());
  for character in text.chars() {
    if matches!(character, '\\' | '*' | '_' | '`' | '[' | ']') {
      out.push('\\');
    }
    if character != '\u{FFFC}' {
      out.push(character);
    }
  }
  out
}

fn escape_label(text: &str) -> String {
  let mut out = String::with_capacity(text.len());
  for character in text.chars() {
    match character {
      '\n' | '\r' | '\u{FFFC}' => out.push(' '),
      '\\' | '[' | ']' => {
        out.push('\\');
        out.push(character);
      }
      _ => out.push(character),
    }
  }
  out
}

fn escape_cell(text: &str) -> String {
  let mut out = String::with_capacity(text.len());
  for character in text.chars() {
    match character {
      '\n' | '\r' | '\u{FFFC}' => out.push(' '),
      '\\' | '|' => {
        out.push('\\');
        out.push(character);
      }
      _ => out.push(character),
    }
  }
  out
}

fn escape_url(url: &str) -> String {
  let mut out = String::with_capacity(url.len());
  for character in url.chars() {
    match character {
      '(' => out.push_str("%28"),
      ')' => out.push_str("%29"),
      ' ' => out.push_str("%20"),
      '\n' | '\r' | '\u{FFFC}' => {}
      _ => out.push(character),
    }
  }
  out
}

#[cfg(test)]
mod tests {
  use super::super::fixture::sample_store;
  use super::super::proto_note::{
    AttachmentInfo, AttributeRun, Font, NoteDocument, NoteVersion, ParagraphStyle, Todo, TopotextString,
  };
  use super::super::shape::note_detail;
  use super::super::store::{self, EntityRow, SqlValue};
  use super::note_markdown;
  use flate2::Compression;
  use flate2::write::GzEncoder;
  use prost::Message;
  use std::collections::HashMap;
  use std::io::Write;

  fn gzip(data: &[u8]) -> Vec<u8> {
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(data).expect("gzip");
    encoder.finish().expect("gzip")
  }

  fn document(text: &str, runs: Vec<AttributeRun>) -> Vec<u8> {
    gzip(
      &NoteDocument {
        version: Some(NoteVersion {
          serialization_version: Some(0),
          minimum_supported_version: Some(0),
          data: Some(TopotextString {
            string: Some(text.into()),
            attribute_run: runs,
          }),
        }),
      }
      .encode_to_vec(),
    )
  }

  fn piece(text: &str, mut run: AttributeRun) -> (String, AttributeRun) {
    run.length = Some(i32::try_from(text.encode_utf16().count()).unwrap_or(i32::MAX));
    (text.to_string(), run)
  }

  fn paragraph(text: &str, style: i32, indent: i32, quote: i32, done: Option<bool>) -> (String, AttributeRun) {
    let mut line = text.to_string();
    line.push('\n');
    piece(
      &line,
      AttributeRun {
        paragraph_style: Some(ParagraphStyle {
          style: Some(style),
          indent: (indent > 0).then_some(indent),
          block_quote_level: (quote > 0).then_some(quote),
          todo: done.map(|done| Todo {
            uuid: None,
            done: Some(done),
          }),
          ..ParagraphStyle::default()
        }),
        ..AttributeRun::default()
      },
    )
  }

  fn text_row(pk: i64, values: &[(&str, &str)], ints: &[(&str, i64)]) -> EntityRow {
    let mut map = HashMap::new();
    for (column, value) in values {
      map.insert((*column).to_string(), SqlValue::Text((*value).to_string()));
    }
    for (column, value) in ints {
      map.insert((*column).to_string(), SqlValue::Int(*value));
    }
    EntityRow { pk, values: map }
  }

  #[test]
  fn file_links_are_unique_even_when_placeholders_are_interleaved() {
    let (_db, path) = sample_store();
    let snap = store::load(&path).expect("store");
    for identifiers in [["png", "png", "pdf", "pdf"], ["png", "pdf", "png", "pdf"]] {
      let runs: Vec<_> = identifiers
        .iter()
        .map(|identifier| AttributeRun {
          length: Some(1),
          attachment_info: Some(AttachmentInfo {
            attachment_identifier: Some((*identifier).to_string()),
            type_uti: Some("public.data".to_string()),
          }),
          ..AttributeRun::default()
        })
        .collect();
      let body = super::render(&snap, "\u{FFFC}\u{FFFC}\u{FFFC}\u{FFFC}", &runs);
      assert_eq!(body.matches("(attachment:png)").count(), 1, "{body}");
      assert_eq!(body.matches("(attachment:pdf)").count(), 1, "{body}");
    }
  }

  #[test]
  fn renders_fixture_markup() {
    let (_db, path) = sample_store();
    let mut snap = store::load(&path).expect("store");
    let note_pk = snap
      .notes
      .iter()
      .find(|note| store::text(note, "identifier") == Some("note-a"))
      .expect("note")
      .pk;
    let data_pk = store::foreign_key(
      snap.notes.iter().find(|note| note.pk == note_pk).expect("note"),
      "noteData",
    )
    .expect("note data");

    let mut parts = vec![paragraph("Title", 0, 0, 0, None)];
    parts.push(paragraph("Heading", 1, 0, 0, None));
    parts.push(paragraph("Subheading", 2, 0, 0, None));
    parts.push(paragraph("dotted", 100, 0, 0, None));
    parts.push(paragraph("dashed", 101, 1, 0, None));
    parts.push(paragraph("first", 102, 0, 0, None));
    parts.push(paragraph("second", 102, 0, 0, None));
    parts.push(paragraph("plain", -1, 0, 0, None));
    parts.push(paragraph("again", 102, 0, 0, None));
    parts.push(paragraph("open", 103, 0, 0, Some(false)));
    parts.push(paragraph("done", 103, 0, 0, Some(true)));
    parts.push(paragraph("quoted", -1, 0, 1, None));
    parts.push(piece("See ", AttributeRun::default()));
    parts.push(piece(
      "bo",
      AttributeRun {
        font_weight: Some(1),
        ..AttributeRun::default()
      },
    ));
    parts.push(piece(
      "ld",
      AttributeRun {
        font_weight: Some(1),
        ..AttributeRun::default()
      },
    ));
    parts.push(piece(" and ", AttributeRun::default()));
    parts.push(piece(
      "site",
      AttributeRun {
        link: Some("https://example.com".into()),
        ..AttributeRun::default()
      },
    ));
    parts.push(piece(" ", AttributeRun::default()));
    parts.push(piece(
      "gone",
      AttributeRun {
        strikethrough: Some(1),
        ..AttributeRun::default()
      },
    ));
    parts.push(piece("\n", AttributeRun::default()));
    parts.push(paragraph("mono one", 4, 0, 0, None));
    parts.push(paragraph("mono two", 4, 0, 0, None));
    parts.push(piece(
      "\u{FFFC}\n",
      AttributeRun {
        attachment_info: Some(AttachmentInfo {
          attachment_identifier: Some("att-table".into()),
          type_uti: Some("com.apple.notes.table".into()),
        }),
        ..AttributeRun::default()
      },
    ));
    parts.push(piece(
      "\u{FFFC}\n",
      AttributeRun {
        attachment_info: Some(AttachmentInfo {
          attachment_identifier: Some("inline-tag".into()),
          type_uti: Some("com.apple.notes.inlinetextattachment.hashtag".into()),
        }),
        ..AttributeRun::default()
      },
    ));
    // Notes' scripting attach stores two placeholders for one attachment, then the next file
    // follows on the same line.
    for _ in 0..2 {
      parts.push(piece(
        "\u{FFFC}",
        AttributeRun {
          attachment_info: Some(AttachmentInfo {
            attachment_identifier: Some("att-1".into()),
            type_uti: Some("public.image".into()),
          }),
          ..AttributeRun::default()
        },
      ));
    }
    parts.push(piece(
      "\u{FFFC}\n",
      AttributeRun {
        attachment_info: Some(AttachmentInfo {
          attachment_identifier: Some("att-gallery".into()),
          type_uti: Some("com.apple.notes.gallery".into()),
        }),
        ..AttributeRun::default()
      },
    ));
    parts.push(piece(
      "\u{FFFC}",
      AttributeRun {
        attachment_info: Some(AttachmentInfo {
          attachment_identifier: Some("missing".into()),
          type_uti: Some("public.png".into()),
        }),
        ..AttributeRun::default()
      },
    ));

    let mut text = String::new();
    let mut runs = Vec::new();
    for (part, run) in parts {
      text.push_str(&part);
      runs.push(run);
    }
    let row = snap.note_data.iter_mut().find(|row| row.pk == data_pk).expect("data");
    row.data = Some(document(&text, runs));
    row.encrypted = false;
    snap.inline_attachments.push(text_row(
      81,
      &[("ZIDENTIFIER", "inline-tag"), ("ZALTTEXT", "#groceries")],
      &[],
    ));
    snap.attachments.push(text_row(
      80,
      &[
        ("ZIDENTIFIER", "att-gallery"),
        ("ZTITLE", "Trip"),
        ("ZTYPEUTI", "com.apple.notes.gallery"),
      ],
      &[("ZNOTE", note_pk)],
    ));

    let note = snap.notes.iter().find(|note| note.pk == note_pk).expect("note");
    let markdown = note_markdown(&snap, note).expect("markdown");
    let expected = "\
# Title
## Heading
### Subheading
- dotted
  - dashed
1. first
2. second
plain
1. again
- [ ] open
- [x] done
> quoted
See **bold** and [site](https://example.com) ~~gone~~
```
mono one
mono two
```
| Right | Left |
| --- | --- |
#groceries
[Beta Unique](attachment:att-1) [Gallery: Trip](attachment:att-gallery)
[public.png](attachment:missing)";
    assert_eq!(markdown, expected);
    assert!(!markdown.contains('\u{FFFC}'));

    let detail = note_detail(&path, &snap, note);
    assert_eq!(detail["body"], markdown);
    assert!(detail.get("snippet").is_none());
    assert!(detail.get("note_data").is_none());
    assert!(detail.get("inline_attachments").is_none());
    assert!(detail.get("password_hint").is_none());
    assert_eq!(detail["is_pinned"], true);
    assert_eq!(detail["folder"]["path"], "Notes");
    assert_eq!(detail["folder"]["account"], "Personal");
    let gallery = detail["attachments"]
      .as_array()
      .expect("attachments")
      .iter()
      .find(|attachment| attachment["identifier"] == "att-gallery")
      .expect("gallery");
    assert_eq!(gallery["title"], "Trip");
    assert_eq!(gallery["type_uti"], "com.apple.notes.gallery");
    assert!(gallery.get("parent_identifier").is_none());
    assert!(gallery.get("mergeable_data").is_none());
    assert!(gallery.get("media").is_none());
  }

  #[test]
  fn bold_point_size_without_a_paragraph_style_reads_back_as_a_heading() {
    let (_db, path) = sample_store();
    let mut snap = store::load(&path).expect("store");
    let note_pk = snap.notes[0].pk;
    let data_pk = store::foreign_key(&snap.notes[0], "noteData").expect("data");
    let sized = |text: &str, points: f32, style: Option<i32>, quote: i32| {
      let mut line = text.to_string();
      line.push('\n');
      piece(
        &line,
        AttributeRun {
          paragraph_style: Some(ParagraphStyle {
            style,
            block_quote_level: (quote > 0).then_some(quote),
            ..ParagraphStyle::default()
          }),
          font: Some(Font {
            point_size: Some(points),
            ..Font::default()
          }),
          font_weight: Some(1),
          ..AttributeRun::default()
        },
      )
    };
    let mut parts = vec![
      sized("Title", 24.0, None, 0),
      sized("Section", 18.0, None, 0),
      sized("small", 17.0, None, 0),
      piece(
        "plain bold\n",
        AttributeRun {
          font_weight: Some(1),
          ..AttributeRun::default()
        },
      ),
      sized("item", 24.0, Some(100), 0),
      sized("Quote", 24.0, None, 1),
      paragraph("Kept", 0, 0, 0, None),
    ];
    parts.push(piece(
      "Mix",
      AttributeRun {
        font: Some(Font {
          point_size: Some(24.0),
          ..Font::default()
        }),
        font_weight: Some(1),
        ..AttributeRun::default()
      },
    ));
    parts.push(piece("ed\n", AttributeRun::default()));
    let mut text = String::new();
    let mut runs = Vec::new();
    for (part, run) in parts {
      text.push_str(&part);
      runs.push(run);
    }
    let row = snap.note_data.iter_mut().find(|row| row.pk == data_pk).expect("data");
    row.data = Some(document(&text, runs));
    row.encrypted = false;
    let note = snap.notes.iter().find(|note| note.pk == note_pk).expect("note");
    assert_eq!(
      note_markdown(&snap, note).as_deref(),
      Some(
        "\
# Title
## Section
**small**
**plain bold**
- **item**
> **Quote**
# Kept
**Mix**ed"
      )
    );
  }

  #[test]
  fn merges_adjacent_inline_runs_and_counts_emoji_in_utf16() {
    let (_db, path) = sample_store();
    let mut snap = store::load(&path).expect("store");
    let note_pk = snap.notes[0].pk;
    let data_pk = store::foreign_key(&snap.notes[0], "noteData").expect("data");
    let mut text = String::new();
    let mut runs = Vec::new();
    for (part, run) in [
      piece("a", AttributeRun::default()),
      piece(
        "em",
        AttributeRun {
          font_weight: Some(2),
          ..AttributeRun::default()
        },
      ),
      piece(" ", AttributeRun::default()),
      piece(
        "both",
        AttributeRun {
          font_weight: Some(3),
          ..AttributeRun::default()
        },
      ),
      piece("\n", AttributeRun::default()),
      piece("a", AttributeRun::default()),
      piece(
        "😀",
        AttributeRun {
          font_weight: Some(1),
          ..AttributeRun::default()
        },
      ),
      piece("b", AttributeRun::default()),
    ] {
      text.push_str(&part);
      runs.push(run);
    }
    assert_eq!(runs[6].length, Some(2), "emoji is one scalar and two UTF-16 units");
    let row = snap.note_data.iter_mut().find(|row| row.pk == data_pk).expect("data");
    row.data = Some(document(&text, runs));
    row.encrypted = false;
    let note = snap.notes.iter().find(|note| note.pk == note_pk).expect("note");
    assert_eq!(
      note_markdown(&snap, note).as_deref(),
      Some("a*em* ***both***\na**😀**b")
    );
  }

  #[test]
  fn skips_missing_encrypted_and_undecodable_bodies() {
    let (_db, path) = sample_store();
    let snap = store::load(&path).expect("store");
    let body = |identifier: &str| {
      let note = store::row_by_identifier(&snap.notes, identifier).expect("note");
      note_markdown(&snap, note)
    };
    assert_eq!(body("note-a").as_deref(), Some("gzip text"));
    assert_eq!(body("note-b").as_deref(), Some("zlib text"));
    assert_eq!(body("note-c"), None);
    assert_eq!(body("note-d"), None);
    assert_eq!(body("note-e"), None);
    assert_eq!(body("note-g"), None);
  }
}

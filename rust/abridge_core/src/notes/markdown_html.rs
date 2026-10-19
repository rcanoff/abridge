//! Markdown to the HTML subset Notes' scripting interface keeps.
//!
//! `notes_get_note` returns Markdown. Notes' `body` setter accepts HTML and then drops most of
//! it: headings become bold (24pt, 18pt, or plain bold), checklists become bullets, quotes become
//! paragraphs, and a whole-paragraph Courier or Menlo font becomes monospaced text. This module
//! emits only markup that setter keeps. Raw HTML is tokenized and rebuilt from that subset.
//! `script`, `style`, and `head` are removed with their contents. Other unknown tags are removed
//! and their text is kept. Tags inside `code` and `pre` stay literal text.

use std::collections::BTreeSet;

use pulldown_cmark::{CowStr, Event, HeadingLevel, Options, Parser, Tag};

use super::error::NotesError;

/// HTML sent to Notes, plus the formatting the body setter cannot keep.
#[derive(Debug, PartialEq, Eq)]
pub(crate) struct RenderedBody {
  pub html: String,
  pub warnings: Vec<String>,
}

/// Agents paste note bodies, not documents. Past this, refuse before the parser allocates.
pub(crate) const MAX_MARKDOWN_BYTES: usize = 512 * 1024;

const ATTACHMENT_PREFIX: &str = "attachment:";

/// An empty Notes line. Notes has no paragraph spacing; the gap between sections is an empty line.
const EMPTY_LINE: &str = "<div><br></div>\n";

pub(crate) fn notes_html(markdown: &str) -> Result<RenderedBody, NotesError> {
  if markdown.len() > MAX_MARKDOWN_BYTES {
    return Err(NotesError::new(
      "body_too_large",
      format!("body is larger than {MAX_MARKDOWN_BYTES} bytes"),
    ));
  }
  let mut options = Options::empty();
  options.insert(Options::ENABLE_TABLES | Options::ENABLE_STRIKETHROUGH | Options::ENABLE_TASKLISTS);
  let (source, inserted) = separate_list_followers(markdown);
  let mut warnings = Warnings::default();
  let mut html_scan = HtmlScan::default();
  let mut stack = vec![Frame::root()];
  let mut seen_block = false;
  let mut after_table = false;
  for (event, range) in Parser::new_ext(&source, options).into_offset_iter() {
    if stack.len() == 1 && matches!(event, Event::Start(_) | Event::Rule) {
      // Leading blank lines are not written: the first line is the note's title.
      if seen_block {
        let mut blank = blank_lines_before(&source, &inserted, range.start);
        // Notes swallows the first empty line after a table, so one more keeps the gap.
        if after_table && blank > 0 {
          blank += 1;
        }
        let root = stack.first_mut().ok_or_else(unbalanced)?;
        for _ in 0..blank {
          root.html.push_str(EMPTY_LINE);
        }
      }
      seen_block = true;
      after_table = false;
    }
    match event {
      Event::Start(tag) => {
        if matches!(tag, Tag::Heading { .. }) {
          warnings.headings = true;
        }
        let header_row =
          matches!(tag, Tag::TableRow) && matches!(stack.last().map(|frame| &frame.kind), Some(Kind::TableHead));
        let mut frame = Frame::open(tag);
        if header_row {
          frame.kind = Kind::TableRow { header: true };
        }
        stack.push(frame);
      }
      Event::End(_) => {
        let frame = stack.pop().ok_or_else(unbalanced)?;
        let parent = stack.last_mut().ok_or_else(unbalanced)?;
        if matches!(parent.kind, Kind::Root) && matches!(frame.kind, Kind::Table) {
          after_table = true;
        }
        frame.finish_into(parent);
      }
      Event::Text(text) => push_escaped(&mut stack, &text)?,
      Event::Code(text) => {
        push_raw(&mut stack, "<code>")?;
        push_escaped(&mut stack, &text)?;
        push_raw(&mut stack, "</code>")?;
      }
      Event::Html(text) | Event::InlineHtml(text) => {
        if in_code(&stack) {
          push_escaped(&mut stack, &text)?;
        } else {
          let sanitized = scan_html(&mut html_scan, &mut warnings, &text);
          push_raw(&mut stack, &sanitized)?;
        }
      }
      Event::SoftBreak | Event::HardBreak => push_break(&mut stack)?,
      Event::Rule => push_raw(&mut stack, "<hr>\n")?,
      // Checked state cannot be stored through the body setter.
      Event::TaskListMarker(_) => warnings.checklists = true,
      Event::FootnoteReference(text) => push_escaped(&mut stack, &text)?,
      Event::InlineMath(text) | Event::DisplayMath(text) => push_escaped(&mut stack, &text)?,
    }
  }
  let frame = stack.pop().ok_or_else(unbalanced)?;
  if !stack.is_empty() || !matches!(frame.kind, Kind::Root) {
    return Err(unbalanced());
  }
  let html = if frame.html.is_empty() {
    "<div><br></div>\n".to_string()
  } else {
    frame.html
  };
  Ok(RenderedBody {
    html,
    warnings: warnings.finish(),
  })
}

fn unbalanced() -> NotesError {
  NotesError::new("notes_error", "could not read the markdown body")
}

fn push_raw(stack: &mut [Frame], text: &str) -> Result<(), NotesError> {
  stack.last_mut().ok_or_else(unbalanced)?.html.push_str(text);
  Ok(())
}

fn push_escaped(stack: &mut [Frame], text: &str) -> Result<(), NotesError> {
  let frame = stack.last_mut().ok_or_else(unbalanced)?;
  push_escaped_into(&mut frame.html, text);
  Ok(())
}

fn push_escaped_into(out: &mut String, text: &str) {
  for character in text.chars() {
    match character {
      '&' => out.push_str("&amp;"),
      '<' => out.push_str("&lt;"),
      '>' => out.push_str("&gt;"),
      '"' => out.push_str("&quot;"),
      _ => out.push(character),
    }
  }
}

fn push_break(stack: &mut [Frame]) -> Result<(), NotesError> {
  let text = if stack.iter().any(|frame| matches!(frame.kind, Kind::TableCell)) {
    " "
  } else if stack.iter().any(|frame| matches!(frame.kind, Kind::Code)) {
    "\n"
  } else {
    // Notes turns <br> into a new line. A newline inside bold or italic stays inside that style.
    "<br>"
  };
  push_raw(stack, text)
}

struct Frame {
  kind: Kind,
  html: String,
}

enum Kind {
  Root,
  Paragraph,
  HtmlBlock,
  Heading(HeadingLevel),
  Quote,
  List { ordered: bool },
  Item,
  Code,
  Table,
  TableHead,
  TableRow { header: bool },
  TableCell,
  Link { href: String, attachment: bool },
  Image { dest: String },
  Strong,
  Emphasis,
  Strike,
  Group,
}

impl Frame {
  fn root() -> Self {
    Self {
      kind: Kind::Root,
      html: String::new(),
    }
  }

  fn open(tag: Tag<'_>) -> Self {
    let kind = match tag {
      Tag::Paragraph => Kind::Paragraph,
      Tag::Heading { level, .. } => Kind::Heading(level),
      Tag::BlockQuote(_) => Kind::Quote,
      Tag::CodeBlock(_) => Kind::Code,
      Tag::HtmlBlock => Kind::HtmlBlock,
      Tag::List(start) => Kind::List {
        ordered: start.is_some(),
      },
      Tag::Item => Kind::Item,
      Tag::Table(_) => Kind::Table,
      Tag::TableHead => Kind::TableHead,
      Tag::TableRow => Kind::TableRow { header: false },
      Tag::TableCell => Kind::TableCell,
      Tag::Emphasis => Kind::Emphasis,
      Tag::Strong => Kind::Strong,
      Tag::Strikethrough => Kind::Strike,
      Tag::Link { dest_url, .. } => link_kind(&dest_url),
      Tag::Image { dest_url, .. } => Kind::Image {
        dest: dest_url.to_string(),
      },
      Tag::FootnoteDefinition(_)
      | Tag::DefinitionList
      | Tag::DefinitionListTitle
      | Tag::DefinitionListDefinition
      | Tag::Superscript
      | Tag::Subscript
      | Tag::MetadataBlock(_) => Kind::Group,
    };
    Self {
      kind,
      html: String::new(),
    }
  }

  fn finish_into(self, parent: &mut Frame) {
    match self.kind {
      Kind::Root => {}
      Kind::HtmlBlock if self.html.is_empty() => {}
      Kind::HtmlBlock if inline_fragment(&self.html) => {
        parent.html.push_str("<div>");
        parent.html.push_str(self.html.trim());
        parent.html.push_str("</div>\n");
      }
      Kind::HtmlBlock => {
        parent.html.push_str(&self.html);
        if !self.html.ends_with('\n') {
          parent.html.push('\n');
        }
      }
      Kind::Paragraph | Kind::Group => {
        let inner = self.html.replace('\n', "<br>");
        if matches!(parent.kind, Kind::Root | Kind::Quote) {
          parent.html.push_str("<div>");
          if inner.is_empty() {
            parent.html.push_str("<br>");
          } else {
            parent.html.push_str(&inner);
          }
          parent.html.push_str("</div>\n");
        } else {
          parent.html.push_str(&inner);
        }
      }
      Kind::Heading(level) => {
        let tag = heading_tag(level);
        parent.html.push('<');
        parent.html.push_str(tag);
        parent.html.push('>');
        parent.html.push_str(&self.html.replace('\n', "<br>"));
        parent.html.push_str("</");
        parent.html.push_str(tag);
        parent.html.push_str(">\n");
      }
      Kind::Quote => parent.html.push_str(&self.html),
      Kind::TableHead => {
        // pulldown puts header cells directly in TableHead, with no TableRow.
        if self.html.starts_with("<tr>") {
          parent.html.push_str(&self.html);
        } else {
          parent.html.push_str("<tr>");
          parent.html.push_str(&self.html);
          parent.html.push_str("</tr>\n");
        }
      }
      Kind::List { ordered } => {
        let tag = if ordered { "ol" } else { "ul" };
        parent.html.push('<');
        parent.html.push_str(tag);
        parent.html.push_str(">\n");
        parent.html.push_str(&self.html);
        parent.html.push_str("</");
        parent.html.push_str(tag);
        parent.html.push_str(">\n");
      }
      Kind::Item => {
        parent.html.push_str("<li>");
        parent.html.push_str(&self.html);
        parent.html.push_str("</li>\n");
      }
      Kind::Code => {
        parent.html.push_str("<pre>");
        parent.html.push_str(&self.html);
        parent.html.push_str("</pre>\n");
      }
      Kind::Table => {
        parent.html.push_str("<table>\n");
        parent.html.push_str(&self.html);
        parent.html.push_str("</table>\n");
      }
      Kind::TableRow { .. } => {
        parent.html.push_str("<tr>");
        parent.html.push_str(&self.html);
        parent.html.push_str("</tr>\n");
      }
      Kind::TableCell => {
        let tag = if matches!(parent.kind, Kind::TableHead | Kind::TableRow { header: true }) {
          "th"
        } else {
          "td"
        };
        parent.html.push('<');
        parent.html.push_str(tag);
        parent.html.push('>');
        parent.html.push_str(&self.html);
        parent.html.push_str("</");
        parent.html.push_str(tag);
        parent.html.push('>');
      }
      Kind::Link { href, attachment } => {
        if attachment {
          push_attachment(
            &mut parent.html,
            &self.html,
            href.strip_prefix(ATTACHMENT_PREFIX).unwrap_or(&href),
          );
        } else {
          parent.html.push_str("<a href=\"");
          push_escaped_into(&mut parent.html, &href);
          parent.html.push_str("\">");
          if self.html.is_empty() {
            push_escaped_into(&mut parent.html, &href);
          } else {
            parent.html.push_str(&self.html);
          }
          parent.html.push_str("</a>");
        }
      }
      Kind::Image { dest } => push_image(&mut parent.html, &self.html, &dest),
      Kind::Strong => wrap(&mut parent.html, "b", &self.html),
      Kind::Emphasis => wrap(&mut parent.html, "i", &self.html),
      Kind::Strike => wrap(&mut parent.html, "strike", &self.html),
    }
  }
}

fn link_kind(dest: &CowStr<'_>) -> Kind {
  Kind::Link {
    attachment: dest.starts_with(ATTACHMENT_PREFIX),
    href: dest.to_string(),
  }
}

fn heading_tag(level: HeadingLevel) -> &'static str {
  match level {
    HeadingLevel::H1 => "h1",
    HeadingLevel::H2 => "h2",
    _ => "h3",
  }
}

fn wrap(out: &mut String, tag: &str, inner: &str) {
  out.push('<');
  out.push_str(tag);
  out.push('>');
  out.push_str(inner);
  out.push_str("</");
  out.push_str(tag);
  out.push('>');
}

fn push_attachment(out: &mut String, label: &str, id: &str) {
  if label.is_empty() {
    push_escaped_into(out, id);
  } else {
    out.push_str(label);
  }
  out.push_str(" (attachment:");
  push_escaped_into(out, id);
  out.push(')');
}

fn push_image(out: &mut String, alt: &str, dest: &str) {
  if let Some(id) = dest.strip_prefix(ATTACHMENT_PREFIX) {
    push_attachment(out, alt, id);
    return;
  }
  if dest.starts_with("data:") {
    out.push_str(alt);
    return;
  }
  if dest.is_empty() {
    out.push_str(alt);
    return;
  }
  out.push_str("<a href=\"");
  push_escaped_into(out, dest);
  out.push_str("\">");
  if alt.is_empty() {
    push_escaped_into(out, dest);
  } else {
    out.push_str(alt);
  }
  out.push_str("</a>");
}

/// `notes_get_note` joins blocks with a single newline. CommonMark would fold an unindented
/// line after a list item into that item, and a table cannot interrupt a paragraph or a list, so
/// this inserts the blank line that keeps the follower a paragraph or a real table. The byte
/// offsets of those inserted newlines are returned so they are not written as empty Notes lines.
fn separate_list_followers(markdown: &str) -> (String, Vec<usize>) {
  let mut out = String::with_capacity(markdown.len());
  let mut inserted = Vec::new();
  let mut in_fence = false;
  let mut after_list_item = false;
  let mut rest = markdown;
  while !rest.is_empty() {
    let (line, newline, tail) = split_line(rest);
    rest = tail;
    if !in_fence && fence_line(line) {
      in_fence = true;
      after_list_item = false;
      push_line(&mut out, line, newline);
      continue;
    }
    if in_fence {
      if fence_line(line) {
        in_fence = false;
      }
      after_list_item = false;
      push_line(&mut out, line, newline);
      continue;
    }
    if line.trim().is_empty() {
      after_list_item = false;
      push_line(&mut out, line, newline);
      continue;
    }
    let before_table = is_table_header(line, rest) && !out.is_empty() && !out.ends_with("\n\n");
    let after_list = after_list_item && !is_indented(line) && !block_start(line) && out.ends_with('\n');
    if before_table || after_list {
      inserted.push(out.len());
      out.push('\n');
    }
    after_list_item = list_marker(line);
    push_line(&mut out, line, newline);
  }
  (out, inserted)
}

/// Blank lines in the Markdown right before the block starting at `start`, not counting newlines
/// `separate_list_followers` inserted. A block's range can run over the blank lines after it, so
/// this walks back from the next block instead of forward from the previous one.
fn blank_lines_before(source: &str, inserted: &[usize], start: usize) -> usize {
  let mut cursor = source[..start].rfind('\n').map_or(0, |index| index + 1);
  let mut blank = 0;
  while cursor > 0 {
    let newline = cursor - 1;
    let previous_start = source[..newline].rfind('\n').map_or(0, |index| index + 1);
    if !source[previous_start..newline].trim().is_empty() {
      break;
    }
    if !inserted.contains(&previous_start) {
      blank += 1;
    }
    cursor = previous_start;
  }
  blank
}

fn is_table_header(line: &str, rest: &str) -> bool {
  let trimmed = line.trim();
  if !trimmed.contains('|') {
    return false;
  }
  let (next, _, _) = split_line(rest);
  is_table_delimiter(next.trim())
}

fn is_table_delimiter(line: &str) -> bool {
  let line = line.trim_matches('|');
  if line.is_empty() {
    return false;
  }
  line.split('|').all(|cell| {
    let cell = cell.trim();
    !cell.is_empty()
      && cell.chars().filter(|character| *character == '-').count() >= 3
      && cell.chars().all(|character| matches!(character, '-' | ':' | ' '))
  })
}

fn split_line(text: &str) -> (&str, bool, &str) {
  match text.find('\n') {
    Some(index) => {
      let (line, tail) = text.split_at(index);
      (line.strip_suffix('\r').unwrap_or(line), true, &tail[1..])
    }
    None => (text.strip_suffix('\r').unwrap_or(text), false, ""),
  }
}

fn push_line(out: &mut String, line: &str, newline: bool) {
  out.push_str(line);
  if newline {
    out.push('\n');
  }
}

fn is_indented(line: &str) -> bool {
  line.starts_with([' ', '\t'])
}

fn fence_line(line: &str) -> bool {
  let trimmed = line.trim_start();
  trimmed.starts_with("```") || trimmed.starts_with("~~~")
}

fn list_marker(line: &str) -> bool {
  let trimmed = line.trim_start();
  if trimmed.starts_with("- ") || trimmed.starts_with("* ") || trimmed.starts_with("+ ") {
    return true;
  }
  let mut digits = 0;
  for character in trimmed.chars() {
    if character.is_ascii_digit() {
      digits += 1;
    } else {
      return digits > 0 && character == '.' && trimmed[digits + 1..].starts_with(' ');
    }
  }
  false
}

fn block_start(line: &str) -> bool {
  let trimmed = line.trim_start();
  trimmed.starts_with(['#', '>', '|'])
    || trimmed.starts_with("```")
    || trimmed.starts_with("~~~")
    || list_marker(line)
    || is_rule(trimmed)
}

fn in_code(stack: &[Frame]) -> bool {
  stack.iter().any(|frame| matches!(frame.kind, Kind::Code))
}

fn inline_fragment(html: &str) -> bool {
  let trimmed = html.trim_start();
  let Some(name) = opening_name(trimmed) else {
    return true;
  };
  !matches!(
    name.as_str(),
    "div" | "p" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "ul" | "ol" | "table" | "pre" | "blockquote"
  )
}

fn opening_name(html: &str) -> Option<String> {
  let rest = html.strip_prefix('<')?.trim_start();
  if rest.starts_with('/') {
    return None;
  }
  let len = ascii_name_len(rest);
  if len == 0 {
    return None;
  }
  Some(rest[..len].to_ascii_lowercase())
}

#[derive(Default)]
struct Warnings {
  headings: bool,
  checklists: bool,
  converted: BTreeSet<String>,
  removed: BTreeSet<String>,
}

impl Warnings {
  fn finish(self) -> Vec<String> {
    let mut warnings = Vec::new();
    if self.headings {
      warnings.push("headings are stored as bold text and read back as # / ## headings".to_string());
    }
    if self.checklists {
      warnings.push("checklists are saved as bullets".to_string());
    }
    if !self.converted.is_empty() {
      warnings.push(format!("HTML tags were converted: {}", join_tags(self.converted)));
    }
    if !self.removed.is_empty() {
      warnings.push(format!("HTML tags were removed: {}", join_tags(self.removed)));
    }
    warnings
  }
}

fn join_tags(tags: BTreeSet<String>) -> String {
  tags.into_iter().collect::<Vec<_>>().join(", ")
}

#[derive(Default)]
struct HtmlScan {
  skip: Option<String>,
  literal: Vec<&'static str>,
  /// Whether each open `<a>` was emitted. A dropped link keeps its text and skips the close tag.
  anchors: Vec<bool>,
}

struct RawTag<'a> {
  source: &'a str,
  close: bool,
  name: String,
  raw_attrs: &'a str,
  self_closing: bool,
}

fn scan_html(scan: &mut HtmlScan, warnings: &mut Warnings, raw: &str) -> String {
  let mut out = String::new();
  let mut rest = raw;
  while !rest.is_empty() {
    if let Some(name) = scan.skip.clone() {
      match close_tag_end(rest, &name) {
        Some(end) => {
          rest = &rest[end..];
          scan.skip = None;
        }
        None => break,
      }
      continue;
    }
    let Some(start) = rest.find('<') else {
      push_text(&mut out, rest);
      break;
    };
    push_text(&mut out, &rest[..start]);
    rest = &rest[start..];
    if rest.starts_with("<!--") {
      rest = skip_until(rest, "-->").unwrap_or("");
      continue;
    }
    if rest.starts_with("<!") || rest.starts_with("<?") {
      rest = skip_until(rest, ">").unwrap_or("");
      continue;
    }
    let Some((tag, next)) = parse_tag(rest) else {
      push_text(&mut out, "<");
      rest = &rest[1..];
      continue;
    };
    emit_tag(&mut out, scan, warnings, &tag);
    rest = next;
  }
  out
}

fn skip_until<'a>(text: &'a str, marker: &str) -> Option<&'a str> {
  text.find(marker).map(|index| &text[index + marker.len()..])
}

fn emit_tag(out: &mut String, scan: &mut HtmlScan, warnings: &mut Warnings, tag: &RawTag<'_>) {
  if !scan.literal.is_empty() {
    emit_literal(out, scan, warnings, tag);
    return;
  }
  if tag.close {
    if tag.name == "a" {
      if scan.anchors.pop().unwrap_or(false) {
        push_close(out, "a");
      }
      return;
    }
    if let Some(emitted) = mapped(&tag.name) {
      push_close(out, emitted);
    }
    return;
  }
  if matches!(tag.name.as_str(), "script" | "style" | "head") {
    warnings.removed.insert(tag.name.clone());
    if !tag.self_closing {
      scan.skip = Some(tag.name.clone());
    }
    return;
  }
  if tag.name == "input" {
    warnings.removed.insert("input".to_string());
    return;
  }
  let Some(emitted) = mapped(&tag.name) else {
    warnings.removed.insert(tag.name.clone());
    return;
  };
  if emitted == "a" {
    match href_from_attrs(tag.raw_attrs) {
      Some(href) => {
        warnings.converted.insert(tag.name.clone());
        out.push_str("<a href=\"");
        push_escaped_into(out, &href);
        out.push_str("\">");
        if tag.self_closing {
          push_close(out, "a");
        } else {
          scan.anchors.push(true);
        }
      }
      None => {
        warnings.removed.insert("a".to_string());
        if !tag.self_closing {
          scan.anchors.push(false);
        }
      }
    }
    return;
  }
  warnings.converted.insert(tag.name.clone());
  if emitted == "br" {
    out.push_str("<br>");
    return;
  }
  out.push('<');
  out.push_str(emitted);
  out.push('>');
  if matches!(emitted, "code" | "pre") && !tag.self_closing {
    scan.literal.push(emitted);
  } else if tag.self_closing {
    push_close(out, emitted);
  }
}

fn emit_literal(out: &mut String, scan: &mut HtmlScan, warnings: &mut Warnings, tag: &RawTag<'_>) {
  let top = scan.literal.last().copied();
  if tag.close && top == Some(tag.name.as_str()) {
    scan.literal.pop();
    push_close(out, tag.name.as_str());
    return;
  }
  if !tag.close && matches!(tag.name.as_str(), "code" | "pre") && !tag.self_closing {
    warnings.converted.insert(tag.name.clone());
    scan.literal.push(if tag.name == "code" { "code" } else { "pre" });
    out.push('<');
    out.push_str(&tag.name);
    out.push('>');
    return;
  }
  push_text(out, tag.source);
}

fn push_close(out: &mut String, name: &str) {
  out.push_str("</");
  out.push_str(name);
  out.push('>');
}

fn mapped(name: &str) -> Option<&'static str> {
  Some(match name {
    "h1" => "h1",
    "h2" => "h2",
    "h3" => "h3",
    "h4" => "h4",
    "h5" => "h5",
    "h6" => "h6",
    "p" => "p",
    "div" => "div",
    "br" => "br",
    "b" => "b",
    "strong" => "b",
    "i" => "i",
    "em" => "i",
    "u" => "u",
    "s" | "del" | "strike" => "strike",
    "a" => "a",
    "ul" => "ul",
    "ol" => "ol",
    "li" => "li",
    "table" => "table",
    "thead" => "thead",
    "tbody" => "tbody",
    "tr" => "tr",
    "th" => "th",
    "td" => "td",
    "code" => "code",
    "pre" => "pre",
    "blockquote" => "blockquote",
    _ => return None,
  })
}

fn parse_tag(input: &str) -> Option<(RawTag<'_>, &str)> {
  let body = input.strip_prefix('<')?;
  let close = body.starts_with('/');
  let body = if close { &body[1..] } else { body };
  let name_len = ascii_name_len(body);
  if name_len == 0 || !body.as_bytes()[0].is_ascii_alphabetic() {
    return None;
  }
  let name = body[..name_len].to_ascii_lowercase();
  let rest = &body[name_len..];
  let (raw_attrs, self_closing, next) = split_tag_end(rest)?;
  let source_len = input.len() - next.len();
  Some((
    RawTag {
      source: &input[..source_len],
      close,
      name,
      raw_attrs,
      self_closing,
    },
    next,
  ))
}

fn split_tag_end(rest: &str) -> Option<(&str, bool, &str)> {
  let bytes = rest.as_bytes();
  let mut index = 0;
  let mut quote = None;
  while index < bytes.len() {
    let byte = bytes[index];
    if let Some(open) = quote {
      if byte == open {
        quote = None;
      }
      index += 1;
      continue;
    }
    match byte {
      b'"' | b'\'' => quote = Some(byte),
      b'>' => {
        let self_closing = index > 0 && bytes[index - 1] == b'/';
        let attrs_end = if self_closing { index - 1 } else { index };
        return Some((&rest[..attrs_end], self_closing, &rest[index + 1..]));
      }
      _ => {}
    }
    index += 1;
  }
  None
}

fn close_tag_end(text: &str, name: &str) -> Option<usize> {
  let lower = text.to_ascii_lowercase();
  let needle = format!("</{name}");
  let mut search = 0;
  while let Some(relative) = lower[search..].find(&needle) {
    let at = search + relative;
    let after_name = at + needle.len();
    let tail = text.get(after_name..)?;
    let trimmed = tail.trim_start();
    if trimmed.starts_with('>') {
      let spaces = tail.len() - trimmed.len();
      return Some(after_name + spaces + 1);
    }
    search = at + needle.len();
  }
  None
}

fn href_from_attrs(raw: &str) -> Option<String> {
  let value = attr_value(raw, "href")?;
  let trimmed = value.trim();
  let lower = trimmed.to_ascii_lowercase();
  if lower.starts_with("https://") || lower.starts_with("http://") || lower.starts_with("mailto:") {
    Some(trimmed.to_string())
  } else {
    None
  }
}

fn attr_value(raw: &str, want: &str) -> Option<String> {
  let mut rest = raw;
  while !rest.is_empty() {
    rest = rest.trim_start();
    if rest.is_empty() || rest.starts_with('/') {
      break;
    }
    let name_len = ascii_name_len(rest);
    if name_len == 0 {
      let skip = rest.chars().next()?.len_utf8();
      rest = &rest[skip..];
      continue;
    }
    let name = &rest[..name_len];
    rest = rest[name_len..].trim_start();
    let (value, next) = attribute_value(rest)?;
    rest = next;
    if name.eq_ignore_ascii_case(want) {
      return Some(decode_entities(&value));
    }
  }
  None
}

fn attribute_value(rest: &str) -> Option<(String, &str)> {
  let Some(after) = rest.strip_prefix('=') else {
    return Some((String::new(), rest));
  };
  let after = after.trim_start();
  let first = after.chars().next()?;
  if first == '"' || first == '\'' {
    let body = &after[first.len_utf8()..];
    let end = body.find(first)?;
    return Some((body[..end].to_string(), &body[end + first.len_utf8()..]));
  }
  let end = after
    .bytes()
    .take_while(|byte| !byte.is_ascii_whitespace() && *byte != b'>')
    .count();
  Some((after[..end].to_string(), &after[end..]))
}

fn ascii_name_len(text: &str) -> usize {
  text
    .bytes()
    .take_while(|byte| byte.is_ascii_alphanumeric() || *byte == b'-' || *byte == b':')
    .count()
}

fn push_text(out: &mut String, text: &str) {
  push_escaped_into(out, &decode_entities(text));
}

fn decode_entities(text: &str) -> String {
  let mut out = String::with_capacity(text.len());
  let mut rest = text;
  while let Some(start) = rest.find('&') {
    out.push_str(&rest[..start]);
    let after = &rest[start + 1..];
    let Some(end) = after.find(';') else {
      out.push('&');
      rest = after;
      break;
    };
    if end > 0
      && end <= 32
      && let Some(character) = decode_entity(&after[..end])
    {
      out.push(character);
      rest = &after[end + 1..];
    } else {
      out.push('&');
      rest = after;
    }
  }
  out.push_str(rest);
  out
}

fn decode_entity(token: &str) -> Option<char> {
  if let Some(hex) = token.strip_prefix('#') {
    let (digits, radix) = if let Some(hex) = hex.strip_prefix(['x', 'X']) {
      (hex, 16)
    } else {
      (hex, 10)
    };
    if digits.is_empty() || !digits.bytes().all(|byte| byte.is_ascii_hexdigit()) {
      return None;
    }
    let code = u32::from_str_radix(digits, radix).ok()?;
    return char::from_u32(code).filter(|character| *character != '\u{0}');
  }
  Some(match token {
    "amp" => '&',
    "lt" => '<',
    "gt" => '>',
    "quot" => '"',
    "apos" => '\'',
    "nbsp" => '\u{00a0}',
    _ => return None,
  })
}

fn is_rule(trimmed: &str) -> bool {
  let marker = trimmed.chars().find(|character| !character.is_whitespace());
  let Some(marker) = marker else {
    return false;
  };
  if !matches!(marker, '-' | '*' | '_') {
    return false;
  }
  let body: String = trimmed.chars().filter(|character| !character.is_whitespace()).collect();
  body.len() >= 3 && body.chars().all(|character| character == marker)
}

#[cfg(test)]
mod tests {
  use super::notes_html;

  fn rendered(markdown: &str) -> super::RenderedBody {
    notes_html(markdown).expect("html")
  }

  fn html(markdown: &str) -> String {
    rendered(markdown).html
  }

  #[test]
  fn leading_heading_is_the_title_line_and_later_headings_use_h2_h3() {
    assert_eq!(
      html("# Title\n\nSecond line\n## Section\n### Smaller\n#### Deep\n"),
      "<h1>Title</h1>\n<div><br></div>\n<div>Second line</div>\n<h2>Section</h2>\n<h3>Smaller</h3>\n<h3>Deep</h3>\n"
    );
  }

  #[test]
  fn blank_lines_between_blocks_become_empty_notes_lines() {
    assert_eq!(
      html("# Plan\n\nIntro\n\n## Steps\n\n- one\n- two\n\n\nDone\n"),
      "<h1>Plan</h1>\n<div><br></div>\n<div>Intro</div>\n<div><br></div>\n<h2>Steps</h2>\n<div><br></div>\n\
       <ul>\n<li>one</li>\n<li>two</li>\n</ul>\n<div><br></div>\n<div><br></div>\n<div>Done</div>\n"
    );
    // No blank line in the Markdown, no empty line in the note.
    assert_eq!(
      html("# Plan\nIntro\n## Steps\n"),
      "<h1>Plan</h1>\n<div>Intro</div>\n<h2>Steps</h2>\n"
    );
    // Leading and trailing blank lines are not written; the first line is the title.
    assert_eq!(html("\n\nIntro\n\n"), "<div>Intro</div>\n");
    // The separators added to keep a list follower or a table out of a list are not empty lines.
    assert_eq!(
      html("- one\nafter\n| A |\n| --- |\n| 1 |\n"),
      "<ul>\n<li>one</li>\n</ul>\n<div>after</div>\n<table>\n<tr><th>A</th></tr>\n<tr><td>1</td></tr>\n</table>\n"
    );
    assert!(
      html("```\na\n\nb\n```\n").contains("a\n\nb"),
      "blank lines inside code stay code"
    );
    // Notes swallows one empty line after a table: one blank line is written as two, none as none.
    let table = "| A |\n| --- |\n| 1 |\n";
    let table_html = "<table>\n<tr><th>A</th></tr>\n<tr><td>1</td></tr>\n</table>\n";
    assert_eq!(
      html(&format!("{table}\nNext\n")),
      format!("{table_html}<div><br></div>\n<div><br></div>\n<div>Next</div>\n")
    );
    assert_eq!(
      html(&format!("{table}## Next\n")),
      format!("{table_html}<h2>Next</h2>\n")
    );
  }

  #[test]
  fn inline_styles_links_and_a_single_newline_are_notes_lines() {
    assert_eq!(
      html("See **bold** and *italic* and ~~gone~~\nnext <b>raw</b>\n"),
      "<div>See <b>bold</b> and <i>italic</i> and <strike>gone</strike><br>next <b>raw</b></div>\n"
    );
    assert_eq!(
      html("Go to [site](https://example.com/a?b=1&c=2).\n"),
      "<div>Go to <a href=\"https://example.com/a?b=1&amp;c=2\">site</a>.</div>\n"
    );
    assert_eq!(html("***both***\n"), "<div><i><b>both</b></i></div>\n");
  }

  #[test]
  fn lists_tasks_quotes_code_tables_dividers_and_attachment_links() {
    assert_eq!(
      html("- dotted\n  - dashed\n1. first\n2. second\nplain\n- [ ] open\n- [x] done\n"),
      "<ul>\n<li>dotted<ul>\n<li>dashed</li>\n</ul>\n</li>\n</ul>\n<ol>\n<li>first</li>\n<li>second</li>\n</ol>\n<div>plain</div>\n<ul>\n<li>open</li>\n<li>done</li>\n</ul>\n"
    );
    assert_eq!(html("> quoted\n"), "<div>quoted</div>\n");
    assert_eq!(
      html("```\nmono one\nmono two\n```\n"),
      "<pre>mono one\nmono two\n</pre>\n"
    );
    assert_eq!(html("use `code` here\n"), "<div>use <code>code</code> here</div>\n");
    assert_eq!(
      html("| Right | Left |\n| --- | --- |\n| a | b |\n"),
      "<table>\n<tr><th>Right</th><th>Left</th></tr>\n<tr><td>a</td><td>b</td></tr>\n</table>\n"
    );
    assert_eq!(html("---\n"), "<hr>\n");
    assert_eq!(
      html("[file](attachment:att-1)\n![shot](data:image/png;base64,aaaa)\n![site](https://example.com/p.png)\n"),
      "<div>file (attachment:att-1)<br>shot<br><a href=\"https://example.com/p.png\">site</a></div>\n"
    );
  }

  #[test]
  fn tables_after_a_paragraph_or_list_need_no_blank_line() {
    let table = "| Item | Qty |\n| --- | --- |\n| Apples | 2 |\n";
    for prefix in ["A paragraph\n", "- Pack charger\n", "1. Pack charger\n"] {
      let output = html(&format!("{prefix}{table}"));
      assert!(output.contains("<table>\n"), "{output}");
      assert!(output.contains("<tr><td>Apples</td><td>2</td></tr>"), "{output}");
      assert!(!output.contains("<li>Pack charger<table>"), "{output}");
    }
    let code = html(&format!("```\nA paragraph\n{table}```\n"));
    assert!(!code.contains("<table>"), "{code}");
  }

  #[test]
  fn empty_and_oversized_bodies() {
    assert_eq!(html(""), "<div><br></div>\n");
    assert_eq!(html("   \n"), "<div><br></div>\n");
    assert!(rendered("plain\n").warnings.is_empty());
    let err = notes_html(&"a".repeat(super::MAX_MARKDOWN_BYTES + 1)).expect_err("size");
    assert_eq!(err.code, "body_too_large");
  }

  #[test]
  fn raw_html_is_rebuilt_from_the_notes_whitelist() {
    assert_eq!(
      html("<strong>b</strong> <em>i</em> <s>s</s> <del>d</del>\n"),
      "<div><b>b</b> <i>i</i> <strike>s</strike> <strike>d</strike></div>\n"
    );
    assert_eq!(html("<div><b>ok</b></div>\n"), "<div><b>ok</b></div>\n");
    assert_eq!(html("<h4>Deep</h4>\n"), "<h4>Deep</h4>\n");
    assert_eq!(html("<blockquote>q</blockquote>\n"), "<blockquote>q</blockquote>\n");
    assert_eq!(
      html("<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>B</td></tr></tbody></table>\n"),
      "<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>B</td></tr></tbody></table>\n"
    );
    assert_eq!(
      html("<ul><li><input type=\"checkbox\" checked> item</li></ul>\n"),
      "<ul><li> item</li></ul>\n"
    );
    assert_eq!(
      html("<a href=\"javascript:alert(1)\">click</a> <a href=\"https://example.com\">ok</a>\n"),
      "<div>click <a href=\"https://example.com\">ok</a></div>\n"
    );
    assert_eq!(
      html("<a href=\"mailto:a@b.c\">mail</a>\n"),
      "<div><a href=\"mailto:a@b.c\">mail</a></div>\n"
    );
    assert_eq!(html("<span class=\"x\">keep</span>\n"), "<div>keep</div>\n");
    assert_eq!(
      html("<div>A &amp; B &lt;tag&gt;</div>\n"),
      "<div>A &amp; B &lt;tag&gt;</div>\n"
    );
    assert_eq!(html("<script>alert(1)</script><b>ok</b>\n"), "<div><b>ok</b></div>\n");
    assert_eq!(html("<style>p{}</style><p>yes</p>\n"), "<p>yes</p>\n");
    assert_eq!(html("<head><title>T</title></head><p>yes</p>\n"), "<p>yes</p>\n");
    assert_eq!(
      html("<pre><code>&lt;b&gt;raw&lt;/b&gt;</code></pre>\n"),
      "<pre><code>&lt;b&gt;raw&lt;/b&gt;</code></pre>\n"
    );
    assert_eq!(html("```\n<b>raw</b>\n```\n"), "<pre>&lt;b&gt;raw&lt;/b&gt;\n</pre>\n");
    assert_eq!(html("use `<b>` here\n"), "<div>use <code>&lt;b&gt;</code> here</div>\n");
  }

  #[test]
  fn warnings_name_only_formatting_notes_cannot_keep() {
    assert_eq!(
      rendered("# Title\n\n- [ ] open\n").warnings,
      vec![
        "headings are stored as bold text and read back as # / ## headings".to_string(),
        "checklists are saved as bullets".to_string()
      ]
    );
    assert_eq!(
      rendered("<strong>b</strong> <em>i</em> <span>x</span> <script>no</script>\n").warnings,
      vec![
        "HTML tags were converted: em, strong".to_string(),
        "HTML tags were removed: script, span".to_string()
      ]
    );
    assert!(rendered("**bold** and `code`\n").warnings.is_empty());
    assert_eq!(rendered("```\n<b>raw</b>\n```\n").warnings, Vec::<String>::new());
  }

  #[test]
  fn html_warnings_name_every_tag_outside_code() {
    let created =
      rendered("# Title\n\n<p>See <b>bold</b> <a href=\"https://example.com/docs\">docs</a></p>\n<div>more</div>\n");
    assert_eq!(
      created.warnings,
      vec![
        "headings are stored as bold text and read back as # / ## headings".to_string(),
        "HTML tags were converted: a, b, div, p".to_string()
      ]
    );
    let updated = rendered("# Next\n\n<p><em>italic</em><br></p>\n<h2>Section</h2>\n");
    assert_eq!(
      updated.warnings,
      vec![
        "headings are stored as bold text and read back as # / ## headings".to_string(),
        "HTML tags were converted: br, em, h2, p".to_string()
      ]
    );
  }
}

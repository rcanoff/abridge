//! Reads an attachment from the Notes account folder next to the store.
//!
//! Layout under `Accounts/<account identifier>/`:
//! - `Media/<media identifier>/[<generation>/]<filename>`: photos, PDFs, video, audio, files.
//! - `FallbackPDFs/<attachment identifier>/<fallbackPDFGeneration>/FallbackPDF.pdf`: scans and
//!   documents Notes keeps as a Paper bundle; this PDF is what Notes shares and exports.
//! - `FallbackImages/<attachment identifier>.{jpg,png}`: drawings rendered as an image.
//!
//! `format` chooses what comes back. `markdown` (the default) puts text in the JSON and returns
//! no file: text documents go through `anydoc` (`text_source` `document`). A scan, an image-only PDF,
//! a photo, or a drawing returns the text Notes saved when Notes has it. When nothing is saved and
//! Vision is enabled, Vision runs. `text_source` `saved` never calls Vision. `text_source` `vision`,
//! and `page` (which implies vision), never fall back to saved text. That path sends each scan or
//! image-only PDF page as a one-page PDF, and a photo or drawing as the original file up to 20 MiB
//! (otherwise a JPEG rendition). Text extraction reads at most 50 MiB and does not load an unsupported
//! file to discover that. `image` returns a viewable JPEG. `original`
//! copies the unmodified file into a private `$TMPDIR/abridge-attachments` directory (not a
//! symlink) and returns that path, with no size cap and no blob. `source_path` is the Notes file.
//! A JPEG rendition is not subject to the 20 MiB cap that still applies when an image cannot be
//! rendered.

use serde_json::{Map, Value, json};

use crate::config::ProviderRequest;
use crate::providers::ProviderBridge;
use std::collections::HashMap;
use std::io::{ErrorKind, Read};
use std::path::{Path, PathBuf};
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant, SystemTime};

use super::error::NotesError;
use super::markdown;
use super::query;
use super::shape;
use super::store::{self, EntityRow, Snapshot};
use super::{AttachmentFile, NotesOutput};
use crate::rendition;

const NO_FILE: &str = "this attachment has no file: tables, link previews, and galleries have none (a gallery's pages \
                       are attachments whose parent_attachment is the gallery), and Notes may not have rendered a \
                       drawing yet";

const GALLERY_UTI: &str = "com.apple.notes.gallery";
const TABLE_UTI: &str = "com.apple.notes.table";
const PAPER_UTIS: [&str; 2] = ["com.apple.paper.doc.scan", "com.apple.paper.doc.pdf"];
const PAGE_PREVIEW_UTIS: [&str; 3] = ["com.apple.paper.doc.scan", "com.apple.paper.doc.pdf", "com.adobe.pdf"];
const IMAGE_HINT: &str = "The image is available with format `image`.";
const PAGE_HINT: &str = "No recognized text. The page image is available with format `image`.";
const ORIGINAL_HINT: &str = "The original file is available with format `original`.";
const DEFAULT_CONTENT_CHARS: u64 = 15_000;
const MAX_CONTENT_CHARS: u64 = 100_000;
const EXPORT_TTL: Duration = Duration::from_secs(24 * 60 * 60);
/// Largest attachment `anydoc` is asked to read. Larger files return `extraction_too_large`.
const EXTRACTION_MAX_BYTES: u64 = 50 * 1024 * 1024;
/// Most PDF pages one markdown call sends to Vision. Further pages set `pages_truncated`.
const MAX_VISION_PAGES: u32 = 20;
const EXTRACTION_HEADER: usize = 1024;
const TEXT_KEYS: [&str; 8] = [
  "text",
  "text_truncated",
  "text_source",
  "description",
  "handwriting",
  "ocr_summary",
  "handwriting_summary",
  "image_classification_summary",
];
/// Stop a text-layer scan that has already taken this long and leave the kind unresolved.
const PAGE_COUNT_BUDGET: Duration = Duration::from_millis(50);
/// Bytes kept across reads so a `/Type /Pages` dictionary split by a chunk boundary is still visible.
const PAGE_TREE_OVERLAP: usize = 512;
const PAGE_TREE_CHUNK: usize = 256 * 1024;
/// How far a `/Type /Pages` name may sit from the `<<` that opens its dictionary.
const PAGE_DICT_BACK: usize = 256;
/// How far `/Count` may sit after `/Type /Pages` before the dictionary's `>>`.
const PAGE_DICT_FORWARD: usize = 8192;
/// Fallback span when the dictionary brackets are not in this chunk.
const PAGE_DICT_WINDOW: usize = 80;
/// Whitespace allowed between `/Type` and `/Pages`. A wider gap is a different object.
const TYPE_PAGES_GAP: usize = 16;
/// Object streams hide the page tree from a byte scan. `lopdf` loads the whole file, so it runs
/// only under this size, and only when the byte scan finds nothing.
const PAGE_COUNT_LOPDF_MAX_BYTES: u64 = 4 * 1024 * 1024;

enum Delivery {
  Markdown,
  Image,
  Original,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum TextChoice {
  /// Saved text when Notes has it; Vision only when nothing is saved and Vision is enabled.
  Auto,
  /// Never calls Vision.
  Saved,
  /// Vision only. No fallback to saved text.
  Vision,
}

pub(crate) fn get_attachment(
  path: &Path,
  arguments: &Value,
  provider: Option<&dyn ProviderBridge>,
  vision_enabled: bool,
) -> Result<NotesOutput, NotesError> {
  let identifier = query::required_identifier(arguments, "attachment_identifier")?;
  let delivery = delivery(arguments)?;
  let window = content_page(arguments)?;
  let page = requested_page(arguments, &delivery)?;
  let choice = requested_text_source(arguments, &delivery, page.is_some())?;
  let snap = store::load(path)?;
  let Some(row) = store::row_by_identifier(&snap.attachments, &identifier) else {
    return Err(NotesError::new("not_found", "attachment not found"));
  };
  if store::flag(row, "isPasswordProtected") {
    return Err(NotesError::new(
      "attachment_locked",
      "the attachment belongs to a password-protected note, so its file is encrypted",
    ));
  }
  let ctx = VisionCtx {
    provider,
    enabled: vision_enabled,
    page,
    choice,
  };
  match delivery {
    Delivery::Markdown => markdown_output(path, &snap, row, window, &ctx),
    Delivery::Image => image_output(path, &snap, row, page),
    Delivery::Original => original_output(path, &snap, row),
  }
}

fn content_page(arguments: &Value) -> Result<(usize, usize), NotesError> {
  let max_characters = match arguments.get("max_characters") {
    None | Some(Value::Null) => DEFAULT_CONTENT_CHARS,
    Some(value) => bounded_u64(value, 1, MAX_CONTENT_CHARS, "max_characters")?,
  };
  let offset = match arguments.get("offset") {
    None | Some(Value::Null) => 0,
    Some(value) => bounded_u64(value, 0, u64::MAX, "offset")?,
  };
  Ok((offset as usize, max_characters as usize))
}

/// The 1-based page markdown or image returns. `original` has no pages.
fn requested_page(arguments: &Value, delivery: &Delivery) -> Result<Option<u32>, NotesError> {
  match arguments.get("page") {
    None | Some(Value::Null) => Ok(None),
    Some(_) if matches!(delivery, Delivery::Original) => Err(NotesError::new(
      "notes_error",
      "page applies only to format markdown or image",
    )),
    Some(value) => {
      let number = bounded_u64(value, 1, u64::from(u32::MAX), "page")?;
      Ok(Some(u32::try_from(number).unwrap_or(u32::MAX)))
    }
  }
}

fn bounded_u64(value: &Value, minimum: u64, maximum: u64, key: &str) -> Result<u64, NotesError> {
  let Some(number) = value.as_u64() else {
    return Err(NotesError::new("notes_error", format!("invalid {key}")));
  };
  if number < minimum || number > maximum {
    return Err(NotesError::new("notes_error", format!("invalid {key}")));
  }
  Ok(number)
}

/// `text_source` chooses saved Notes text or a fresh Vision read. It is markdown-only. `page` is a
/// Vision page, so an explicit `saved` choice cannot be combined with it. `ocr` is not an argument.
fn requested_text_source(arguments: &Value, delivery: &Delivery, page: bool) -> Result<TextChoice, NotesError> {
  if arguments.get("ocr").is_some_and(|value| !value.is_null()) {
    return Err(NotesError::new(
      "invalid_arguments",
      "ocr was removed; use text_source saved or vision",
    ));
  }
  match arguments.get("text_source") {
    None | Some(Value::Null) => Ok(TextChoice::Auto),
    Some(_) if !matches!(delivery, Delivery::Markdown) => Err(NotesError::new(
      "invalid_arguments",
      "text_source applies only to format markdown",
    )),
    Some(Value::String(value)) => match value.as_str() {
      "saved" if page => Err(NotesError::new(
        "invalid_arguments",
        "page reads one page with Vision, so it cannot be combined with text_source saved",
      )),
      "saved" => Ok(TextChoice::Saved),
      "vision" => Ok(TextChoice::Vision),
      _ => Err(NotesError::new(
        "invalid_arguments",
        "text_source must be saved or vision",
      )),
    },
    _ => Err(NotesError::new(
      "invalid_arguments",
      "text_source must be saved or vision",
    )),
  }
}

fn delivery(arguments: &Value) -> Result<Delivery, NotesError> {
  match arguments.get("format") {
    None | Some(Value::Null) => Ok(Delivery::Markdown),
    Some(Value::String(value)) => match value.as_str() {
      "markdown" => Ok(Delivery::Markdown),
      "image" => Ok(Delivery::Image),
      "original" => Ok(Delivery::Original),
      _ => Err(NotesError::new(
        "notes_error",
        "format must be markdown, image, or original",
      )),
    },
    _ => Err(NotesError::new("notes_error", "invalid format")),
  }
}

fn markdown_output(
  path: &Path,
  snap: &Snapshot,
  row: &EntityRow,
  window: (usize, usize),
  ctx: &VisionCtx<'_>,
) -> Result<NotesOutput, NotesError> {
  let uti = store::text(row, "typeUTI").unwrap_or("");
  let view = if uti == GALLERY_UTI {
    if ctx.page.is_some() {
      return Err(page_not_applicable());
    }
    if ctx.choice == TextChoice::Vision {
      return Err(vision_not_applicable());
    }
    MarkdownView::gallery(gallery_markdown(snap, row)?)
  } else if uti == TABLE_UTI {
    if ctx.page.is_some() {
      return Err(page_not_applicable());
    }
    if ctx.choice == TextChoice::Vision {
      return Err(vision_not_applicable());
    }
    MarkdownView::table(markdown::table_markdown(row).ok_or_else(no_file)?)
  } else if PAPER_UTIS.contains(&uti) {
    paper_view(path, snap, row, ctx)?
  } else if is_visual(uti, None) {
    visual_attachment(path, snap, row, ctx)?
  } else {
    match locate(path, snap, row) {
      Ok(file_path) => file_markdown(&file_path, row, Some(ctx))?,
      Err(error) => stored_view(row, uti, error)?,
    }
  };
  let file_path = locate(path, snap, row).ok();
  Ok(payload_output(
    path,
    snap,
    row,
    Payload {
      format: "markdown",
      content: Some(view.content),
      rendition: None,
      file: None,
      source_path: file_path.as_deref(),
      export_path: None,
      page: Some(window),
      pdf_page: view.pdf_page,
      page_count: view.page_count,
      text_source: view.text_source,
      pages_truncated: view.pages_truncated,
      next_page: view.next_page,
      compact: false,
    },
  ))
}

fn paper_view(path: &Path, snap: &Snapshot, row: &EntityRow, ctx: &VisionCtx<'_>) -> Result<MarkdownView, NotesError> {
  let located = locate(path, snap, row);
  if ctx.choice == TextChoice::Saved {
    return saved_scan(row, located.is_ok(), located.err());
  }
  if ctx.wants_vision() {
    if let Some(page) = ctx.page {
      match &located {
        Ok(file_path) => validate_pdf_file(file_path, page)?,
        Err(_) if page > 1 => return Err(page_unrendered(page)),
        Err(_) => {}
      }
    }
    let provider = ctx.require_vision()?;
    if let Ok(file_path) = &located {
      return match vision_pdf_file(file_path, ctx.page, provider)? {
        PdfVision::Text(view) => Ok(view),
        PdfVision::Missed { cause, pages } => Err(vision_failed(cause.as_deref(), pages)),
        PdfVision::NotCalled => Err(vision_failed(None, page_count(path, snap, row))),
      };
    }
    return Err(located.err().unwrap_or_else(|| vision_failed(None, None)));
  }
  let ocr = shape::recognized_text(row);
  if !ocr.is_empty() {
    return Ok(MarkdownView::saved(ocr));
  }
  if let Some(provider) = ctx.vision_provider()
    && let Ok(file_path) = &located
  {
    match vision_pdf_file(file_path, None, provider)? {
      PdfVision::Text(view) => return Ok(view),
      PdfVision::Missed { cause, pages } => return Ok(automatic_vision_miss(cause, pages)),
      PdfVision::NotCalled => {}
    }
  }
  saved_scan(row, located.is_ok(), located.err())
}

fn saved_scan(row: &EntityRow, file_ok: bool, missing: Option<NotesError>) -> Result<MarkdownView, NotesError> {
  let ocr = shape::recognized_text(row);
  if !ocr.is_empty() {
    return Ok(MarkdownView::saved(ocr));
  }
  if file_ok {
    Ok(MarkdownView::saved(PAGE_HINT.to_string()))
  } else {
    Err(missing.unwrap_or_else(|| vision_failed(None, None)))
  }
}

fn visual_attachment(
  path: &Path,
  snap: &Snapshot,
  row: &EntityRow,
  ctx: &VisionCtx<'_>,
) -> Result<MarkdownView, NotesError> {
  if ctx.page.is_some_and(|page| page > 1) {
    return Err(single_image_page());
  }
  let uti = store::text(row, "typeUTI").unwrap_or("");
  match locate(path, snap, row) {
    Ok(file_path) => visual_view(row, Some(&file_path), true, Some(ctx)),
    Err(error) => {
      if ctx.wants_vision() {
        ctx.require_vision()?;
        return Err(error);
      }
      stored_view(row, uti, error)
    }
  }
}

fn markdown_from_file(path: &Path, row: &EntityRow) -> Result<String, NotesError> {
  file_markdown(path, row, None).map(|view| view.content)
}

fn file_markdown(path: &Path, row: &EntityRow, ctx: Option<&VisionCtx<'_>>) -> Result<MarkdownView, NotesError> {
  let page = ctx.and_then(|ctx| ctx.page);
  let uti = store::text(row, "typeUTI").unwrap_or("");
  if is_visual(uti, None) {
    return visual_view(row, Some(path), true, ctx);
  }
  let mut file = match crate::private_dir::open_regular(path) {
    Ok(file) => file,
    Err(err) if err.kind() == ErrorKind::InvalidInput => return unsupported_view(row, page),
    Err(err) if err.kind() == ErrorKind::NotFound => return Err(unavailable()),
    Err(_) => return Err(unavailable()),
  };
  let len = file.metadata().map_err(|_| unavailable())?.len();
  if len > EXTRACTION_MAX_BYTES {
    let mut probe = [0u8; 64];
    let n = file.read(&mut probe).unwrap_or(0);
    if sniff_bytes(&probe[..n]).is_some_and(|mime| mime.starts_with("image/")) {
      return visual_view(row, Some(path), true, ctx);
    }
    return Err(extraction_too_large());
  }
  let mut header = [0u8; EXTRACTION_HEADER];
  let n = file.read(&mut header).map_err(|_| unavailable())?;
  let header = &header[..n];
  if sniff_bytes(header).is_some_and(|mime| mime.starts_with("image/")) {
    return visual_view(row, Some(path), true, ctx);
  }
  if !should_extract(uti, path, header) {
    if ctx.is_some_and(|ctx| ctx.choice == TextChoice::Vision) {
      return Err(vision_not_applicable());
    }
    return unsupported_view(row, page);
  }
  let mut bytes = Vec::with_capacity(n);
  bytes.extend_from_slice(header);
  file
    .take(EXTRACTION_MAX_BYTES + 1 - bytes.len() as u64)
    .read_to_end(&mut bytes)
    .map_err(|_| unavailable())?;
  if bytes.len() as u64 > EXTRACTION_MAX_BYTES {
    return Err(extraction_too_large());
  }
  let format = anydoc::Format::from_bytes(&bytes).or_else(|| anydoc::Format::from_path(path));
  let pdf = format == Some(anydoc::Format::Pdf);
  let choice = ctx.map(|ctx| ctx.choice).unwrap_or(TextChoice::Auto);
  if page.is_some() && !pdf {
    return Err(page_not_applicable());
  }
  if choice == TextChoice::Vision && !pdf {
    return Err(vision_not_applicable());
  }
  if pdf && (choice == TextChoice::Vision || page.is_some()) {
    return vision_pdf_choice(&bytes, ctx);
  }
  match anydoc::to_markdown_bytes(&bytes, format) {
    Ok(markdown) => {
      let trimmed = markdown.trim();
      if trimmed.is_empty() {
        let ocr = shape::recognized_text(row);
        if ocr.is_empty() {
          Err(unreadable("empty"))
        } else if choice == TextChoice::Vision {
          Err(vision_failed(None, None))
        } else {
          Ok(MarkdownView::saved(ocr))
        }
      } else if pdf {
        Ok(MarkdownView::document(super::pdf_text::repair_tracked_markdown(
          trimmed, &bytes,
        )))
      } else {
        Ok(MarkdownView::document(trimmed.to_string()))
      }
    }
    Err(error) => match error {
      anydoc::ConvertError::NeedsOcr { .. } => image_only_pdf(row, &bytes, ctx),
      anydoc::ConvertError::Unsupported(_) => unsupported_view(row, page),
      anydoc::ConvertError::Encrypted => Err(NotesError::new(
        "attachment_encrypted",
        "the file is encrypted, so its text cannot be read",
      )),
      anydoc::ConvertError::Io(_) => Err(unavailable()),
      other => {
        let ocr = shape::recognized_text(row);
        if choice == TextChoice::Vision || page.is_some() {
          Err(vision_failed(None, None))
        } else if ocr.is_empty() {
          Err(unreadable(other.code()))
        } else {
          Ok(MarkdownView::saved(ocr))
        }
      }
    },
  }
}

fn vision_pdf_choice(bytes: &[u8], ctx: Option<&VisionCtx<'_>>) -> Result<MarkdownView, NotesError> {
  let Some(ctx) = ctx else {
    return Err(vision_unavailable());
  };
  if let Some(page) = ctx.page {
    validate_pdf_bytes(bytes, page)?;
  }
  let provider = ctx.require_vision()?;
  match vision_pdf_bytes(bytes, ctx.page, provider)? {
    PdfVision::Text(view) => Ok(view),
    PdfVision::Missed { cause, pages } => Err(vision_failed(cause.as_deref(), pages)),
    PdfVision::NotCalled => Err(vision_failed(None, pdf_page_count(bytes))),
  }
}

/// An image-only PDF (`anydoc` `NeedsOcr`). Saved text wins unless the caller asked for Vision.
/// With nothing saved, Vision runs when it is enabled. Explicit Vision never falls back.
fn image_only_pdf(row: &EntityRow, bytes: &[u8], ctx: Option<&VisionCtx<'_>>) -> Result<MarkdownView, NotesError> {
  let choice = ctx.map(|ctx| ctx.choice).unwrap_or(TextChoice::Auto);
  let page = ctx.and_then(|ctx| ctx.page);
  if choice == TextChoice::Vision || page.is_some() {
    return vision_pdf_choice(bytes, ctx);
  }
  if choice == TextChoice::Saved {
    return Ok(MarkdownView::saved(scan_markdown(row)));
  }
  let ocr = shape::recognized_text(row);
  if !ocr.is_empty() {
    return Ok(MarkdownView::saved(ocr));
  }
  if let Some(provider) = ctx.and_then(VisionCtx::vision_provider) {
    match vision_pdf_bytes(bytes, None, provider)? {
      PdfVision::Text(view) => return Ok(view),
      PdfVision::Missed { cause, pages } => return Ok(automatic_vision_miss(cause, pages)),
      PdfVision::NotCalled => {}
    }
  }
  Ok(MarkdownView::saved(scan_markdown(row)))
}

fn extraction_too_large() -> NotesError {
  NotesError::new(
    "extraction_too_large",
    format!(
      "the file is larger than {} MiB, so its text was not read",
      EXTRACTION_MAX_BYTES / 1024 / 1024
    ),
  )
}

/// Documents anydoc can convert. Video and audio headers are refused before the rest of the file
/// is read; a document signature still wins when the extension or UTI is wrong.
fn should_extract(uti: &str, path: &Path, header: &[u8]) -> bool {
  if sniff_bytes(header).is_some_and(|mime| mime.starts_with("video/") || mime.starts_with("audio/")) {
    return false;
  }
  header_is_document(header) || anydoc::Format::from_path(path).is_some() || uti_is_document(uti)
}

fn header_is_document(bytes: &[u8]) -> bool {
  bytes.starts_with(b"%PDF")
    || bytes.starts_with(b"{\\rtf")
    || bytes.starts_with(&[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    || bytes.starts_with(b"PK\x03\x04")
    || bytes.windows(5).any(|window| window == b"%PDF-")
}

fn uti_is_document(uti: &str) -> bool {
  matches!(
    uti,
    "com.adobe.pdf"
      | "public.rtf"
      | "public.comma-separated-values-text"
      | "public.delimited-values-text"
      | "com.microsoft.word.doc"
      | "org.openxmlformats.wordprocessingml.document"
      | "com.microsoft.excel.xls"
      | "org.openxmlformats.spreadsheetml.sheet"
      | "com.microsoft.powerpoint.ppt"
      | "org.openxmlformats.presentationml.presentation"
      | "org.oasis-open.opendocument.text"
      | "org.oasis-open.opendocument.spreadsheet"
      | "org.oasis-open.opendocument.presentation"
      | "org.idpf.epub-container"
      | "public.epub"
  )
}

/// Document text for the search index. Photos, scans, tables, and galleries already contribute
/// their stored text; a PDF or other document contributes the same Markdown `get_attachment` returns.
pub(super) fn indexed_document_text(path: &Path, snap: &Snapshot, row: &EntityRow) -> String {
  let uti = store::text(row, "typeUTI").unwrap_or("");
  if store::flag(row, "isPasswordProtected")
    || uti == TABLE_UTI
    || uti == GALLERY_UTI
    || PAPER_UTIS.contains(&uti)
    || is_visual(uti, None)
  {
    return String::new();
  }
  let Ok(file) = locate(path, snap, row) else {
    return String::new();
  };
  if is_visual(uti, Some(&file)) {
    return String::new();
  }
  match markdown_from_file(&file, row) {
    Ok(markdown) if markdown != PAGE_HINT && markdown != ORIGINAL_HINT => markdown,
    _ => String::new(),
  }
}

fn stored_text_or(row: &EntityRow, uti: &str, error: NotesError) -> Result<String, NotesError> {
  if is_visual(uti, None) {
    let text = visual_markdown(row, false);
    if text.is_empty() { Err(error) } else { Ok(text) }
  } else {
    let ocr = shape::recognized_text(row);
    if ocr.is_empty() { Err(error) } else { Ok(ocr) }
  }
}

fn scan_markdown(row: &EntityRow) -> String {
  let ocr = shape::recognized_text(row);
  if ocr.is_empty() { PAGE_HINT.to_string() } else { ocr }
}

fn visual_markdown(row: &EntityRow, image_available: bool) -> String {
  let mut parts = Vec::new();
  let ocr = shape::recognized_text(row);
  if !ocr.is_empty() {
    parts.push(ocr);
  }
  let classification = shape::image_classification(row);
  if !classification.is_empty() {
    parts.push(classification);
  }
  if image_available {
    parts.push(IMAGE_HINT.to_string());
  }
  parts.join("\n\n")
}

fn gallery_markdown(snap: &Snapshot, gallery: &EntityRow) -> Result<String, NotesError> {
  let pages = shape::gallery_pages(snap, gallery);
  if pages.is_empty() {
    return Err(no_file());
  }
  let lines = pages
    .into_iter()
    .map(|page| {
      let identifier = store::text(page, "identifier").unwrap_or("");
      format!("- [{}](attachment:{identifier})", escape_label(&page_label(snap, page)))
    })
    .collect::<Vec<_>>();
  Ok(lines.join("\n"))
}

fn page_label(snap: &Snapshot, row: &EntityRow) -> String {
  store::foreign_key(row, "media")
    .and_then(|pk| store::row_by_pk(&snap.media, pk))
    .and_then(|media| store::text(media, "filename"))
    .filter(|name| !name.is_empty())
    .or_else(|| store::text(row, "title").filter(|title| !title.is_empty()))
    .unwrap_or("Page")
    .to_string()
}

fn escape_label(text: &str) -> String {
  let mut out = String::with_capacity(text.len());
  for character in text.chars() {
    match character {
      '\n' | '\r' => out.push(' '),
      '\\' | '[' | ']' => {
        out.push('\\');
        out.push(character);
      }
      _ => out.push(character),
    }
  }
  out
}

fn image_output(path: &Path, snap: &Snapshot, row: &EntityRow, page: Option<u32>) -> Result<NotesOutput, NotesError> {
  let file_path = locate(path, snap, row)?;
  let uti = store::text(row, "typeUTI").unwrap_or("");
  let source_type = mime_type(&file_path);
  if wants_page_jpeg(uti, &file_path) {
    return pdf_page_output(path, snap, row, &file_path, page.unwrap_or(1));
  }
  if page.is_some_and(|number| number > 1) {
    return Err(NotesError::new(
      "notes_error",
      "page applies only to a PDF or a scan; this attachment is a single image",
    ));
  }
  if !is_visual(uti, Some(&file_path)) {
    return Err(NotesError::new(
      "attachment_not_viewable",
      "format image is for a photo, a drawing, a scan, or a PDF",
    ));
  }
  let size = std::fs::metadata(&file_path).map_err(|_| unavailable())?.len();
  let (bytes, mime_type, rendition_kind) = if rendition::needs_rendition(source_type, size) {
    match rendition::jpeg_rendition(&file_path) {
      Some(jpeg) => (jpeg, "image/jpeg", Some("jpeg")),
      None => {
        let file = raw_file(&file_path)?;
        (file.bytes, file.mime_type, None)
      }
    }
  } else {
    let file = raw_file(&file_path)?;
    (file.bytes, file.mime_type, None)
  };
  Ok(payload_output(
    path,
    snap,
    row,
    Payload {
      format: "image",
      content: None,
      rendition: rendition_kind,
      file: Some(AttachmentFile {
        bytes,
        mime_type,
        uri: file_uri(&file_path),
      }),
      source_path: Some(&file_path),
      export_path: None,
      page: None,
      pdf_page: None,
      page_count: None,
      text_source: None,
      pages_truncated: false,
      next_page: None,
      compact: true,
    },
  ))
}

/// One page of a PDF or scan as a JPEG. The JSON names the page and, when the PDF could be read,
/// how many pages it has, so a caller knows to ask for the rest.
fn pdf_page_output(
  path: &Path,
  snap: &Snapshot,
  row: &EntityRow,
  file_path: &Path,
  page: u32,
) -> Result<NotesOutput, NotesError> {
  let pdf = read_pdf(file_path, page)?;
  let rendered = match pdf.as_deref() {
    Some(bytes) => rendition::jpeg_pdf_page(bytes, page),
    None => rendition::PdfPage::Unrendered { page_count: None },
  };
  let (jpeg, page_count) = match rendered {
    rendition::PdfPage::Rendered { jpeg, page_count } => (Some(jpeg), Some(page_count)),
    rendition::PdfPage::OutOfRange { page_count } => {
      return Err(NotesError::new(
        "page_out_of_range",
        format!("page {page} does not exist; the PDF has {page_count} page(s)"),
      ));
    }
    // `sips` renders a PDF's first page directly, so page 1 survives a PDF `lopdf` cannot split.
    rendition::PdfPage::Unrendered { page_count } if page == 1 => (rendition::jpeg_rendition(file_path), page_count),
    rendition::PdfPage::Unrendered { .. } => {
      return Err(NotesError::new(
        "page_unrendered",
        format!("page {page} could not be rendered; use format original for the whole PDF"),
      ));
    }
  };
  let (file, rendition_kind) = match jpeg {
    Some(bytes) => (
      AttachmentFile {
        bytes,
        mime_type: "image/jpeg",
        uri: file_uri(file_path),
      },
      Some("jpeg_page"),
    ),
    None => (raw_file(file_path)?, None),
  };
  Ok(payload_output(
    path,
    snap,
    row,
    Payload {
      format: "image",
      content: None,
      rendition: rendition_kind,
      file: Some(file),
      source_path: Some(file_path),
      export_path: None,
      page: None,
      pdf_page: rendition_kind.map(|_| (page, page_count)),
      page_count: None,
      text_source: None,
      pages_truncated: false,
      next_page: None,
      compact: true,
    },
  ))
}

/// The PDF's bytes for page splitting, or `None` past the extraction limit. Only page 1 can be
/// rendered without reading the file (by `sips`), so a later page of a too-large PDF is refused.
fn read_pdf(file_path: &Path, page: u32) -> Result<Option<Vec<u8>>, NotesError> {
  let file = crate::private_dir::open_regular(file_path).map_err(|_| unavailable())?;
  let len = file.metadata().map_err(|_| unavailable())?.len();
  if len > EXTRACTION_MAX_BYTES {
    if page == 1 {
      return Ok(None);
    }
    return Err(NotesError::new(
      "extraction_too_large",
      format!(
        "the PDF is larger than {} MiB, so only page 1 can be rendered; use format original for the whole file",
        EXTRACTION_MAX_BYTES / 1024 / 1024
      ),
    ));
  }
  let mut bytes = Vec::new();
  file
    .take(EXTRACTION_MAX_BYTES + 1)
    .read_to_end(&mut bytes)
    .map_err(|_| unavailable())?;
  Ok(Some(bytes))
}

fn original_output(path: &Path, snap: &Snapshot, row: &EntityRow) -> Result<NotesOutput, NotesError> {
  let source = locate(path, snap, row)?;
  let identifier = store::text(row, "identifier")
    .and_then(component)
    .ok_or_else(unavailable)?;
  let export = export_original(identifier, &source)?;
  Ok(payload_output(
    path,
    snap,
    row,
    Payload {
      format: "original",
      content: None,
      rendition: None,
      file: None,
      source_path: Some(&source),
      export_path: Some(&export),
      page: None,
      pdf_page: None,
      page_count: None,
      text_source: None,
      pages_truncated: false,
      next_page: None,
      compact: true,
    },
  ))
}

struct Payload<'a> {
  format: &'a str,
  content: Option<String>,
  rendition: Option<&'a str>,
  file: Option<AttachmentFile>,
  source_path: Option<&'a Path>,
  export_path: Option<&'a Path>,
  page: Option<(usize, usize)>,
  /// The rendered PDF page and the PDF's page count, when one page was requested.
  pdf_page: Option<(u32, Option<u32>)>,
  /// Page count for a multi-page markdown result that does not name one `page`.
  page_count: Option<u32>,
  text_source: Option<&'static str>,
  pages_truncated: bool,
  next_page: Option<u32>,
  compact: bool,
}

fn payload_output(path: &Path, snap: &Snapshot, row: &EntityRow, delivered: Payload<'_>) -> NotesOutput {
  let Payload {
    format,
    content,
    rendition,
    file,
    source_path,
    export_path,
    page,
    pdf_page,
    page_count: delivered_count,
    text_source,
    pages_truncated,
    next_page,
    compact,
  } = delivered;
  let mut payload =
    shape::attachment_detail(path, snap, row, shape::AttachmentView::File).unwrap_or_else(|| Value::Object(Map::new()));
  if let Some(object) = payload.as_object_mut() {
    object.insert("format".into(), Value::String(format.to_string()));
    if compact {
      for key in TEXT_KEYS {
        object.remove(key);
      }
    }
    if let Some(content) = content.filter(|content| !content.is_empty()) {
      let (shown, truncated, next_offset) = match page {
        Some((offset, max_characters)) => page_text(&content, offset, max_characters),
        None => (content, false, None),
      };
      if !shown.is_empty() {
        object.insert("content".into(), Value::String(shown));
      }
      if truncated {
        object.insert("content_truncated".into(), Value::Bool(true));
        if let Some(next_offset) = next_offset {
          object.insert("next_offset".into(), Value::from(next_offset as u64));
        }
      }
    }
    if let Some(kind) = rendition {
      object.insert("rendition".into(), Value::String(kind.to_string()));
    }
    if let Some((number, pdf_count)) = pdf_page {
      object.insert("page".into(), Value::from(number));
      if let Some(pdf_count) = pdf_count {
        object.insert("page_count".into(), Value::from(pdf_count));
      }
    } else if let Some(page_count) = delivered_count {
      object.insert("page_count".into(), Value::from(page_count));
    }
    let kind = attachment_kind(path, snap, row);
    object.insert("kind".into(), Value::String(kind.to_string()));
    if (kind == "scan" || kind == "pdf")
      && !object.contains_key("page_count")
      && let Some(count) = page_count(path, snap, row)
    {
      object.insert("page_count".into(), Value::from(count));
    }
    if let Some(source) = text_source {
      object.insert("text_source".into(), Value::String(source.to_string()));
    }
    if pages_truncated {
      object.insert("pages_truncated".into(), Value::Bool(true));
    }
    if let Some(next_page) = next_page {
      object.insert("next_page".into(), Value::from(next_page));
    }
    if let Some(path) = source_path {
      object.insert("source_path".into(), Value::String(absolute_path(path)));
      if let Ok(metadata) = std::fs::metadata(path) {
        object.insert("file_size".into(), Value::from(metadata.len()));
      }
    }
    if let Some(path) = export_path {
      object.insert("file_path".into(), Value::String(absolute_path(path)));
    }
  }
  NotesOutput { payload, file }
}

/// Copies `source` to `$TMPDIR/abridge-attachments/<identifier>/<file name>` (directory 0700, file
/// 0600) and deletes export entries older than 24 hours. The root is rejected when it is a symlink
/// or not a directory. Cleanup and the copy do not follow links. The copy has no size cap.
fn export_original(identifier: &str, source: &Path) -> Result<PathBuf, NotesError> {
  export_original_in(&std::env::temp_dir().join("abridge-attachments"), identifier, source)
}

fn export_original_in(root: &Path, identifier: &str, source: &Path) -> Result<PathBuf, NotesError> {
  let name = source
    .file_name()
    .and_then(|name| name.to_str())
    .and_then(component)
    .ok_or_else(export_failed)?;
  let dir = crate::private_dir::OpenDir::establish(root).map_err(|_| export_failed())?;
  dir.remove_older_than(EXPORT_TTL);
  let child = dir.ensure_child(identifier).map_err(|_| export_failed())?;
  child.write_file(name, source).map_err(|_| export_failed())
}

fn export_failed() -> NotesError {
  NotesError::new("notes_error", "could not copy the attachment out of the Notes store")
}

fn page_text(text: &str, offset: usize, max_characters: usize) -> (String, bool, Option<usize>) {
  let indices: Vec<usize> = text.char_indices().map(|(index, _)| index).collect();
  let total = indices.len();
  if offset >= total {
    return (String::new(), false, None);
  }
  let start = indices[offset];
  let end_char = offset.saturating_add(max_characters);
  if end_char >= total {
    return (text[start..].to_string(), false, None);
  }
  (text[start..indices[end_char]].to_string(), true, Some(end_char))
}

fn absolute_path(path: &Path) -> String {
  if path.is_absolute() {
    return path.to_string_lossy().into_owned();
  }
  std::env::current_dir()
    .map(|cwd| cwd.join(path))
    .unwrap_or_else(|_| path.to_path_buf())
    .to_string_lossy()
    .into_owned()
}

fn raw_file(path: &Path) -> Result<AttachmentFile, NotesError> {
  Ok(AttachmentFile {
    bytes: read_bounded(path)?,
    mime_type: mime_type(path),
    uri: file_uri(path),
  })
}

fn wants_page_jpeg(uti: &str, path: &Path) -> bool {
  page_preview(Some(uti)) || mime_type(path) == "application/pdf"
}

fn is_visual(uti: &str, path: Option<&Path>) -> bool {
  uti.starts_with("public.image")
    || uti.starts_with("com.apple.drawing")
    || uti.starts_with("com.apple.notes.sketch")
    || matches!(
      uti,
      "public.jpeg"
        | "public.jpg"
        | "public.png"
        | "public.heic"
        | "public.heif"
        | "public.tiff"
        | "public.gif"
        | "public.webp"
        | "public.bmp"
        | "public.camera-raw-image"
        | "com.compuserve.gif"
    )
    || path.is_some_and(|path| mime_type(path).starts_with("image/"))
}

fn page_preview(uti: Option<&str>) -> bool {
  uti.is_some_and(|uti| PAGE_PREVIEW_UTIS.contains(&uti))
}

fn unreadable(code: &str) -> NotesError {
  NotesError::new(
    "attachment_unreadable",
    format!("the file could not be converted to Markdown ({code})"),
  )
}

/// Byte length of the attachment file on disk, when Notes has downloaded it.
pub(super) fn on_disk_len(store_path: &Path, snap: &Snapshot, row: &EntityRow) -> Option<u64> {
  let path = locate(store_path, snap, row).ok()?;
  std::fs::metadata(path).ok().map(|metadata| metadata.len())
}

pub(super) fn locate(store_path: &Path, snap: &Snapshot, row: &EntityRow) -> Result<PathBuf, NotesError> {
  let account = account_dir(store_path, snap, row).ok_or_else(unavailable)?;
  if let Some(media) = store::foreign_key(row, "media").and_then(|pk| store::row_by_pk(&snap.media, pk)) {
    return media_path(&account, media)
      .filter(|path| path.is_file())
      .ok_or_else(unavailable);
  }
  let identifier = store::text(row, "identifier")
    .and_then(component)
    .ok_or_else(unavailable)?;
  if let Some(generation) = store::text(row, "fallbackPDFGeneration") {
    let generation = component(generation).ok_or_else(unavailable)?;
    let pdf = account
      .join("FallbackPDFs")
      .join(identifier)
      .join(generation)
      .join("FallbackPDF.pdf");
    return if pdf.is_file() { Ok(pdf) } else { Err(unavailable()) };
  }
  ["jpg", "png"]
    .iter()
    .map(|extension| account.join("FallbackImages").join(format!("{identifier}.{extension}")))
    .find(|path| path.is_file())
    .ok_or_else(|| NotesError::new("attachment_has_no_file", NO_FILE))
}

fn media_path(account: &Path, media: &EntityRow) -> Option<PathBuf> {
  let mut path = account
    .join("Media")
    .join(component(store::text(media, "identifier")?)?);
  if let Some(generation) = store::text(media, "generation") {
    path.push(component(generation)?);
  }
  path.push(component(store::text(media, "filename")?)?);
  Some(path)
}

fn account_dir(store_path: &Path, snap: &Snapshot, attachment: &EntityRow) -> Option<PathBuf> {
  let note = store::row_by_pk(&snap.notes, store::foreign_key(attachment, "note")?)?;
  let account = store::row_by_pk(&snap.accounts, store::foreign_key(note, "account")?)?;
  let identifier = component(store::text(account, "identifier")?)?;
  Some(store_path.parent()?.join("Accounts").join(identifier))
}

/// One path component from store text; anything that could leave the account folder is refused.
fn component(value: &str) -> Option<&str> {
  let safe = !value.is_empty() && value != "." && value != ".." && !value.contains(['/', '\0']);
  safe.then_some(value)
}

fn no_file() -> NotesError {
  NotesError::new("attachment_has_no_file", NO_FILE)
}

fn unavailable() -> NotesError {
  NotesError::new(
    "attachment_file_unavailable",
    "the attachment's file is not on this Mac; Notes may not have downloaded it from iCloud yet",
  )
}

fn read_bounded(path: &Path) -> Result<Vec<u8>, NotesError> {
  let file = crate::private_dir::open_regular(path).map_err(|_| unavailable())?;
  let len = file.metadata().map_err(|_| unavailable())?.len();
  if len > rendition::MAX_RESOURCE_BYTES {
    return Err(too_large());
  }
  let mut bytes = Vec::new();
  file
    .take(rendition::MAX_RESOURCE_BYTES + 1)
    .read_to_end(&mut bytes)
    .map_err(|_| unavailable())?;
  if bytes.len() as u64 > rendition::MAX_RESOURCE_BYTES {
    return Err(too_large());
  }
  Ok(bytes)
}

fn too_large() -> NotesError {
  NotesError::new(
    "attachment_too_large",
    format!(
      "the attachment's file is larger than {} MiB, the most one call returns",
      rendition::MAX_RESOURCE_BYTES / 1024 / 1024
    ),
  )
}

fn mime_type(path: &Path) -> &'static str {
  sniff_mime(path).unwrap_or_else(|| mime_from_extension(path))
}

/// MIME type from the file header. Extension is not consulted.
fn sniff_mime(path: &Path) -> Option<&'static str> {
  let mut header = [0u8; 64];
  let mut file = crate::private_dir::open_regular(path).ok()?;
  let read = std::io::Read::read(&mut file, &mut header).ok()?;
  sniff_bytes(&header[..read])
}

fn sniff_bytes(bytes: &[u8]) -> Option<&'static str> {
  if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
    return Some("image/jpeg");
  }
  if bytes.starts_with(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
    return Some("image/png");
  }
  if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
    return Some("image/gif");
  }
  if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
    return Some("image/webp");
  }
  if bytes.starts_with(b"%PDF") {
    return Some("application/pdf");
  }
  if bytes.starts_with(b"II*\0") || bytes.starts_with(b"MM\0*") {
    return Some("image/tiff");
  }
  ftyp_mime(bytes)
}

/// ISO BMFF `ftyp` brands. HEIF/HEIC wins over a compatible MP4 brand in the same box.
fn ftyp_mime(bytes: &[u8]) -> Option<&'static str> {
  if bytes.len() < 12 || &bytes[4..8] != b"ftyp" {
    return None;
  }
  let declared = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as usize;
  let end = if declared < 16 {
    bytes.len()
  } else {
    declared.min(bytes.len())
  };
  let mut heic = false;
  let mut heif = false;
  let mut quicktime = false;
  let mut audio = false;
  let mut mp4 = false;
  let mut offset = 8;
  while offset + 4 <= end {
    if offset != 12 {
      match &bytes[offset..offset + 4] {
        b"heic" | b"heix" => heic = true,
        b"mif1" | b"msf1" | b"hevc" => heif = true,
        b"qt  " => quicktime = true,
        b"M4A " | b"M4B " => audio = true,
        b"isom" | b"iso2" | b"mp41" | b"mp42" | b"avc1" | b"mp71" | b"M4V " | b"dash" | b"iso5" | b"iso6" => mp4 = true,
        _ => {}
      }
    }
    offset += 4;
  }
  if heic {
    Some("image/heic")
  } else if heif {
    Some("image/heif")
  } else if quicktime {
    Some("video/quicktime")
  } else if audio {
    Some("audio/mp4")
  } else if mp4 {
    Some("video/mp4")
  } else {
    Some("application/octet-stream")
  }
}

fn mime_from_extension(path: &Path) -> &'static str {
  let extension = path
    .extension()
    .and_then(|value| value.to_str())
    .map(str::to_ascii_lowercase);
  match extension.as_deref() {
    Some("jpg" | "jpeg") => "image/jpeg",
    Some("png") => "image/png",
    Some("gif") => "image/gif",
    Some("webp") => "image/webp",
    Some("heic") => "image/heic",
    Some("heif") => "image/heif",
    Some("tif" | "tiff") => "image/tiff",
    Some("bmp") => "image/bmp",
    Some("pdf") => "application/pdf",
    Some("mov") => "video/quicktime",
    Some("mp4") => "video/mp4",
    Some("m4a") => "audio/mp4",
    Some("mp3") => "audio/mpeg",
    Some("wav") => "audio/wav",
    Some("txt") => "text/plain",
    _ => "application/octet-stream",
  }
}

fn file_uri(path: &Path) -> String {
  let mut uri = String::from("file://");
  for byte in path.to_string_lossy().bytes() {
    if byte.is_ascii_alphanumeric() || b"/-._~".contains(&byte) {
      uri.push(byte as char);
    } else {
      uri.push_str(&format!("%{byte:02X}"));
    }
  }
  uri
}

struct VisionCtx<'a> {
  provider: Option<&'a dyn ProviderBridge>,
  enabled: bool,
  page: Option<u32>,
  choice: TextChoice,
}

impl VisionCtx<'_> {
  /// Explicit Vision, or `page`, which implies Vision and does not fall back.
  fn wants_vision(&self) -> bool {
    self.choice == TextChoice::Vision || self.page.is_some()
  }

  fn vision_provider(&self) -> Option<&dyn ProviderBridge> {
    if self.enabled { self.provider } else { None }
  }

  fn require_vision(&self) -> Result<&dyn ProviderBridge, NotesError> {
    self.vision_provider().ok_or_else(vision_unavailable)
  }
}

struct MarkdownView {
  content: String,
  text_source: Option<&'static str>,
  pdf_page: Option<(u32, Option<u32>)>,
  page_count: Option<u32>,
  pages_truncated: bool,
  next_page: Option<u32>,
}

impl MarkdownView {
  fn document(content: String) -> Self {
    Self::sourced(content, Some("document"))
  }

  fn table(content: String) -> Self {
    Self::sourced(content, Some("table"))
  }

  fn gallery(content: String) -> Self {
    Self::sourced(content, Some("gallery"))
  }

  fn saved(content: String) -> Self {
    Self::sourced(content, Some("saved"))
  }

  fn sourced(content: String, text_source: Option<&'static str>) -> Self {
    Self {
      content,
      text_source,
      pdf_page: None,
      page_count: None,
      pages_truncated: false,
      next_page: None,
    }
  }

  fn vision_image(content: String) -> Self {
    Self {
      text_source: Some("vision"),
      ..Self::document(content)
    }
  }

  fn vision_pdf(content: String, requested: Option<u32>, page_count: u32, plan: &PagePlan) -> Self {
    Self {
      content,
      text_source: Some("vision"),
      pdf_page: requested.map(|number| (number, Some(page_count))),
      page_count: requested.is_none().then_some(page_count),
      pages_truncated: plan.truncated,
      next_page: plan.next_page,
    }
  }
}

#[derive(Debug)]
pub(super) struct PagePlan {
  pub(super) numbers: Vec<u32>,
  pub(super) truncated: bool,
  pub(super) next_page: Option<u32>,
}

fn stored_view(row: &EntityRow, uti: &str, error: NotesError) -> Result<MarkdownView, NotesError> {
  stored_text_or(row, uti, error).map(MarkdownView::saved)
}

fn visual_view(
  row: &EntityRow,
  path: Option<&Path>,
  image_available: bool,
  ctx: Option<&VisionCtx<'_>>,
) -> Result<MarkdownView, NotesError> {
  if ctx.and_then(|ctx| ctx.page).is_some_and(|page| page > 1) {
    return Err(single_image_page());
  }
  let choice = ctx.map(|ctx| ctx.choice).unwrap_or(TextChoice::Auto);
  if choice == TextChoice::Saved {
    return Ok(MarkdownView::saved(visual_markdown(row, image_available)));
  }
  let explicit = choice == TextChoice::Vision || ctx.and_then(|ctx| ctx.page).is_some();
  if explicit {
    let ctx = ctx.ok_or_else(vision_unavailable)?;
    let provider = ctx.require_vision()?;
    let missed = match path {
      Some(path) => match vision_image(path, provider) {
        Ok(content) => return Ok(MarkdownView::vision_image(content)),
        Err(miss) => miss,
      },
      None => VisionMiss {
        cause: None,
        called: false,
      },
    };
    return Err(vision_failed(missed.cause.as_deref(), None));
  }
  if !shape::recognized_text(row).is_empty() {
    return Ok(MarkdownView::saved(visual_markdown(row, image_available)));
  }
  if let Some(provider) = ctx.and_then(VisionCtx::vision_provider)
    && let Some(path) = path
  {
    match vision_image(path, provider) {
      Ok(content) => return Ok(MarkdownView::vision_image(content)),
      Err(miss) if miss.called => return Ok(automatic_vision_miss(miss.cause, None)),
      Err(_) => {}
    }
  }
  Ok(MarkdownView::saved(visual_markdown(row, image_available)))
}

fn unsupported_view(row: &EntityRow, page: Option<u32>) -> Result<MarkdownView, NotesError> {
  if page.is_some() {
    return Err(page_not_applicable());
  }
  let ocr = shape::recognized_text(row);
  if ocr.is_empty() {
    Ok(MarkdownView::saved(ORIGINAL_HINT.to_string()))
  } else {
    Ok(MarkdownView::saved(ocr))
  }
}

fn vision_image(path: &Path, provider: &dyn ProviderBridge) -> Result<String, VisionMiss> {
  let Some(size) = std::fs::metadata(path).ok().map(|metadata| metadata.len()) else {
    return Err(VisionMiss {
      cause: None,
      called: false,
    });
  };
  // Vision reads the original HEIC, PNG, JPEG, or TIFF. Above the resource cap, send a JPEG.
  let Some(bytes) = (if size <= rendition::MAX_RESOURCE_BYTES {
    read_bounded(path).ok()
  } else {
    rendition::jpeg_rendition(path)
  }) else {
    return Err(VisionMiss {
      cause: None,
      called: false,
    });
  };
  recognize_pages(&[(1, bytes)], provider).map_err(|cause| VisionMiss { cause, called: true })
}

fn vision_pdf_file(path: &Path, page: Option<u32>, provider: &dyn ProviderBridge) -> Result<PdfVision, NotesError> {
  let Some(bytes) = read_pdf(path, page.unwrap_or(1))? else {
    return Ok(PdfVision::NotCalled);
  };
  vision_pdf_bytes(&bytes, page, provider)
}

fn vision_pdf_bytes(bytes: &[u8], page: Option<u32>, provider: &dyn ProviderBridge) -> Result<PdfVision, NotesError> {
  let Some(count) = pdf_page_count(bytes) else {
    if let Some(page) = page.filter(|page| *page > 1) {
      return Err(page_unrendered(page));
    }
    return Ok(PdfVision::NotCalled);
  };
  let plan = plan_pages(count, page)?;
  let mut rendered = Vec::with_capacity(plan.numbers.len());
  for number in &plan.numbers {
    match rendition::pdf_single_page(bytes, *number) {
      rendition::PdfSinglePage::Page { bytes, .. } => rendered.push((*number, bytes)),
      rendition::PdfSinglePage::OutOfRange { page_count } => return Err(page_out_of_range(*number, page_count)),
      rendition::PdfSinglePage::Unrendered { .. } => return Ok(PdfVision::NotCalled),
    }
  }
  match recognize_pages(&rendered, provider) {
    Ok(content) => Ok(PdfVision::Text(MarkdownView::vision_pdf(content, page, count, &plan))),
    Err(cause) => Ok(PdfVision::Missed {
      cause,
      pages: Some(count),
    }),
  }
}

fn validate_pdf_file(path: &Path, page: u32) -> Result<(), NotesError> {
  match read_pdf(path, page)? {
    Some(bytes) => validate_pdf_bytes(&bytes, page),
    None => Ok(()),
  }
}

fn validate_pdf_bytes(bytes: &[u8], page: u32) -> Result<(), NotesError> {
  match pdf_page_count(bytes) {
    Some(count) if page == 0 || page > count => Err(page_out_of_range(page, count)),
    Some(_) => Ok(()),
    None if page > 1 => Err(page_unrendered(page)),
    None => Ok(()),
  }
}

fn pdf_page_count(pdf: &[u8]) -> Option<u32> {
  let document = lopdf::Document::load_mem(pdf).ok()?;
  let count = u32::try_from(document.get_pages().len()).unwrap_or(0);
  (count > 0).then_some(count)
}

pub(super) fn plan_pages(page_count: u32, requested: Option<u32>) -> Result<PagePlan, NotesError> {
  if let Some(page) = requested {
    if page == 0 || page > page_count {
      return Err(page_out_of_range(page, page_count));
    }
    return Ok(PagePlan {
      numbers: vec![page],
      truncated: false,
      next_page: None,
    });
  }
  if page_count == 0 {
    return Err(page_unrendered(1));
  }
  let last = page_count.min(MAX_VISION_PAGES);
  let truncated = page_count > MAX_VISION_PAGES;
  Ok(PagePlan {
    numbers: (1..=last).collect(),
    truncated,
    next_page: truncated.then_some(last + 1),
  })
}

pub(super) fn recognize_pages(
  pages: &[(u32, Vec<u8>)],
  provider: &dyn ProviderBridge,
) -> Result<String, Option<String>> {
  if pages.is_empty() {
    return Err(None);
  }
  let mut gathered = Vec::with_capacity(pages.len());
  for (number, image) in pages {
    gathered.push((*number, recognize_one(image, provider)?));
  }
  let text = assemble_pages(&gathered);
  if text.is_empty() { Err(None) } else { Ok(text) }
}

fn assemble_pages(pages: &[(u32, String)]) -> String {
  let sections: Vec<(u32, &str)> = pages
    .iter()
    .map(|(number, text)| (*number, text.trim()))
    .filter(|(_, text)| !text.is_empty())
    .collect();
  if sections.is_empty() {
    return String::new();
  }
  if pages.len() == 1 {
    return sections[0].1.to_string();
  }
  sections
    .into_iter()
    .map(|(number, text)| format!("## Page {number}\n\n{text}"))
    .collect::<Vec<_>>()
    .join("\n\n")
}

fn recognize_one(image: &[u8], provider: &dyn ProviderBridge) -> Result<String, Option<String>> {
  let image_data = base64::Engine::encode(&base64::engine::general_purpose::STANDARD, image);
  let response = provider.call_provider(ProviderRequest {
    provider: "vision".into(),
    operation: "recognize_text".into(),
    payload_json: json!({ "image_data": image_data }).to_string(),
  });
  if !response.ok {
    return Err(bridge_error_message(&response));
  }
  let text = serde_json::from_str::<Value>(&response.payload_json)
    .map(|raw| crate::agent_shape::vision_text(&raw))
    .unwrap_or_default();
  let text = text.trim().to_string();
  if text.is_empty() { Err(None) } else { Ok(text) }
}

fn bridge_error_message(response: &crate::config::ProviderResponse) -> Option<String> {
  let raw = response.error_json.as_deref()?;
  let parsed = serde_json::from_str::<Value>(raw).ok();
  let message = parsed
    .as_ref()
    .and_then(|value| value.get("message"))
    .and_then(Value::as_str)
    .unwrap_or("")
    .trim()
    .trim_end_matches('.');
  if message.is_empty() {
    None
  } else {
    Some(message.to_string())
  }
}

struct VisionMiss {
  cause: Option<String>,
  called: bool,
}

enum PdfVision {
  Text(MarkdownView),
  Missed { cause: Option<String>, pages: Option<u32> },
  NotCalled,
}

fn automatic_vision_miss(cause: Option<String>, pages: Option<u32>) -> MarkdownView {
  let mut view = MarkdownView::vision_image(vision_tried_message(cause.as_deref(), pages));
  view.page_count = pages;
  view
}

fn vision_tried_message(cause: Option<&str>, pages: Option<u32>) -> String {
  vision_outcome_message("Vision was tried and could not read it", cause, pages)
}

fn vision_failed(cause: Option<&str>, pages: Option<u32>) -> NotesError {
  NotesError::new(
    "vision_failed",
    vision_outcome_message("Vision did not return text", cause, pages),
  )
}

fn vision_outcome_message(lead: &str, cause: Option<&str>, pages: Option<u32>) -> String {
  let next = match pages.filter(|count| *count > 0) {
    Some(count) => format!("View it with format image (page 1 of {count})."),
    None => "View it with format image.".to_string(),
  };
  match cause.map(str::trim).filter(|cause| !cause.is_empty()) {
    Some(cause) => format!("{lead}: {cause}. {next}"),
    None => format!("{lead}. {next}"),
  }
}

fn vision_unavailable() -> NotesError {
  NotesError::new(
    "vision_unavailable",
    "Vision is disabled, so this attachment cannot be read with text_source vision",
  )
}

fn vision_not_applicable() -> NotesError {
  NotesError::new(
    "invalid_arguments",
    "text_source vision applies to a scan, an image-only PDF, a photo, or a drawing",
  )
}

/// Agent-facing kind: `scan`, `pdf`, `photo`, `drawing`, `document`, `audio`, `video`, `file`,
/// `gallery`, or `link`. `scan` is a Paper scan or an image-only PDF. `pdf` is a PDF with a text
/// layer. `document` is a non-PDF anydoc format.
pub(crate) fn attachment_kind(store_path: &Path, snap: &Snapshot, row: &EntityRow) -> &'static str {
  let uti = store::text(row, "typeUTI").unwrap_or("");
  if uti == GALLERY_UTI {
    return "gallery";
  }
  if is_link_uti(uti) {
    return "link";
  }
  if is_drawing_uti(uti) {
    return "drawing";
  }
  if is_visual(uti, None) {
    return "photo";
  }
  if is_audio_uti(uti) {
    return "audio";
  }
  if is_video_uti(uti) {
    return "video";
  }
  if PAPER_UTIS.contains(&uti) {
    return "scan";
  }
  let path = locate(store_path, snap, row).ok();
  if let Some(path) = path.as_deref()
    && let Some(mime) = sniff_mime(path)
  {
    if mime.starts_with("audio/") {
      return "audio";
    }
    if mime.starts_with("video/") {
      return "video";
    }
    if mime.starts_with("image/") {
      return "photo";
    }
  }
  if is_pdf_uti(uti)
    || path
      .as_deref()
      .is_some_and(|path| sniff_mime(path) == Some("application/pdf"))
  {
    let image_only = path
      .as_deref()
      .is_some_and(|path| pdf_has_text_layer(path) == Some(false));
    return if image_only { "scan" } else { "pdf" };
  }
  if uti_is_document(uti) || path.as_deref().is_some_and(path_is_document) {
    return "document";
  }
  "file"
}

/// Page count for a scan or PDF.
///
/// One streaming pass keeps the largest `/Count` on a `/Type /Pages` dictionary. That is the
/// page-tree root: a nested node counts only its own pages. When the pass finds nothing and the
/// file is at most 4 MiB, `lopdf` reads it, which covers a page tree stored in an object stream.
/// `None` for other kinds, a missing file, or a count that is not there. Never guesses 1.
/// Cached in memory by file path, length, and mtime.
pub(crate) fn page_count(store_path: &Path, snap: &Snapshot, row: &EntityRow) -> Option<u32> {
  let kind = attachment_kind(store_path, snap, row);
  if kind != "scan" && kind != "pdf" {
    return None;
  }
  let path = locate(store_path, snap, row).ok()?;
  let metadata = std::fs::metadata(&path).ok()?;
  let modified = metadata.modified().ok()?;
  let len = metadata.len();
  let key = PageCacheKey {
    path: path.clone(),
    modified,
    len,
  };
  if let Some(cached) = PAGE_CACHE.lock().ok().and_then(|guard| guard.get(&key).copied()) {
    return cached;
  }
  let count = pdf_page_count_of_file(&path, len);
  if let Ok(mut guard) = PAGE_CACHE.lock() {
    guard.insert(key, count);
  }
  count
}

#[derive(Hash, Eq, PartialEq, Clone)]
struct PageCacheKey {
  path: PathBuf,
  modified: SystemTime,
  len: u64,
}

static PAGE_CACHE: LazyLock<Mutex<HashMap<PageCacheKey, Option<u32>>>> = LazyLock::new(|| Mutex::new(HashMap::new()));

fn is_link_uti(uti: &str) -> bool {
  let uti = uti.to_ascii_lowercase();
  uti == "public.url"
    || uti == "public.html"
    || uti.contains("linkpreview")
    || uti.contains("urlattachment")
    || uti.ends_with(".url")
}

fn is_drawing_uti(uti: &str) -> bool {
  uti.starts_with("com.apple.drawing") || uti.starts_with("com.apple.notes.sketch")
}

fn is_audio_uti(uti: &str) -> bool {
  uti.starts_with("public.audio")
    || uti == "public.mp3"
    || uti == "public.mpeg-4-audio"
    || uti == "public.aiff-audio"
    || uti == "public.aifc-audio"
    || uti == "com.microsoft.waveform-audio"
    || uti.contains("m4a-audio")
}

fn is_video_uti(uti: &str) -> bool {
  uti.starts_with("public.movie")
    || uti.starts_with("public.video")
    || uti == "public.mpeg-4"
    || uti == "com.apple.quicktime-movie"
    || uti == "public.avi"
}

fn is_pdf_uti(uti: &str) -> bool {
  uti == "com.adobe.pdf" || uti == "public.pdf"
}

fn path_is_document(path: &Path) -> bool {
  let extension = path
    .extension()
    .and_then(|value| value.to_str())
    .map(|value| value.to_ascii_lowercase());
  extension.is_some_and(|extension| extension != "pdf") && anydoc::Format::from_path(path).is_some()
}

/// `Some(true)` when `/Font` is found, `Some(false)` when the file was scanned and has none,
/// `None` when the scan ran out of time.
fn pdf_has_text_layer(path: &Path) -> Option<bool> {
  let started = Instant::now();
  let mut file = crate::private_dir::open_regular(path).ok()?;
  let mut overlap = Vec::new();
  let mut chunk = [0u8; 64 * 1024];
  loop {
    if started.elapsed() > PAGE_COUNT_BUDGET {
      return None;
    }
    let read = std::io::Read::read(&mut file, &mut chunk).ok()?;
    if read == 0 {
      return Some(false);
    }
    overlap.extend_from_slice(&chunk[..read]);
    if find_subslice(&overlap, b"/Font").is_some() {
      return Some(true);
    }
    if overlap.len() > 16 {
      overlap = overlap[overlap.len() - 8..].to_vec();
    }
  }
}

fn pdf_page_count_of_file(path: &Path, len: u64) -> Option<u32> {
  if let Some(count) = scan_page_tree_count(path) {
    return Some(count);
  }
  if len > PAGE_COUNT_LOPDF_MAX_BYTES {
    return None;
  }
  let bytes = read_bounded(path).ok()?;
  pdf_page_count(&bytes)
}

/// Largest `/Count` on a `/Type /Pages` dictionary, reading the file once.
fn scan_page_tree_count(path: &Path) -> Option<u32> {
  let mut file = crate::private_dir::open_regular(path).ok()?;
  let mut overlap = Vec::new();
  let mut chunk = vec![0u8; PAGE_TREE_CHUNK];
  let mut best: Option<u32> = None;
  loop {
    let read = match std::io::Read::read(&mut file, &mut chunk) {
      Ok(0) => return best.filter(|count| *count > 0),
      Ok(read) => read,
      Err(_) => return best.filter(|count| *count > 0),
    };
    overlap.extend_from_slice(&chunk[..read]);
    if let Some(count) = max_pages_count(&overlap) {
      best = Some(best.unwrap_or(0).max(count));
    }
    if overlap.len() > PAGE_TREE_OVERLAP {
      let start = overlap.len() - PAGE_TREE_OVERLAP;
      overlap.copy_within(start.., 0);
      overlap.truncate(PAGE_TREE_OVERLAP);
    }
  }
}

fn max_pages_count(bytes: &[u8]) -> Option<u32> {
  let mut best = None;
  let mut start = 0;
  while let Some(rel) = find_subslice(&bytes[start..], b"/Type") {
    let at = start + rel;
    if let Some(count) = pages_count_at(bytes, at) {
      best = Some(best.unwrap_or(0).max(count));
    }
    start = at + 5;
  }
  best
}

/// `/Count` for a `/Type /Pages` name at `at`, or `None` when this `/Type` is not the Pages tree.
fn pages_count_at(bytes: &[u8], at: usize) -> Option<u32> {
  let mut index = at + 5;
  let gap_end = (index + TYPE_PAGES_GAP).min(bytes.len());
  while index < gap_end && is_pdf_whitespace(bytes[index]) {
    index += 1;
  }
  if !bytes.get(index..)?.starts_with(b"/Pages") {
    return None;
  }
  let name_end = index + 6;
  if bytes.get(name_end).is_some_and(|byte| is_pdf_name_byte(*byte)) {
    return None;
  }
  let dict = dictionary_around(bytes, at).unwrap_or_else(|| {
    let window_start = at.saturating_sub(PAGE_DICT_WINDOW);
    let window_end = (name_end + PAGE_DICT_WINDOW).min(bytes.len());
    &bytes[window_start..window_end]
  });
  count_near(dict)
}

/// Bytes inside the `<<` `>>` dictionary that contains `inside`, when both brackets are near it.
fn dictionary_around(bytes: &[u8], inside: usize) -> Option<&[u8]> {
  let mut start = inside.min(bytes.len());
  let mut walked = 0;
  while start > 0 && walked < PAGE_DICT_BACK {
    if bytes[start - 1] == b'<' && start > 1 && bytes[start - 2] == b'<' {
      start -= 2;
      break;
    }
    if bytes[start - 1] == b'>' && start > 1 && bytes[start - 2] == b'>' {
      return None;
    }
    start -= 1;
    walked += 1;
  }
  if walked == PAGE_DICT_BACK {
    return None;
  }
  let mut end = inside;
  walked = 0;
  while end + 1 < bytes.len() && walked < PAGE_DICT_FORWARD {
    if bytes[end] == b'>' && bytes[end + 1] == b'>' {
      return Some(&bytes[start..end]);
    }
    end += 1;
    walked += 1;
  }
  None
}

fn count_near(window: &[u8]) -> Option<u32> {
  let needle = b"/Count";
  let mut start = 0;
  let mut best = None;
  while let Some(rel) = find_subslice(&window[start..], needle) {
    let at = start + rel;
    let mut index = at + needle.len();
    if window.get(index).is_some_and(|byte| is_pdf_name_byte(*byte)) {
      start = index;
      continue;
    }
    while index < window.len() && is_pdf_whitespace(window[index]) {
      index += 1;
    }
    if index < window.len() && window[index].is_ascii_digit() {
      let mut number: u32 = 0;
      while index < window.len() && window[index].is_ascii_digit() {
        number = number
          .saturating_mul(10)
          .saturating_add(u32::from(window[index] - b'0'));
        index += 1;
      }
      if number > 0 {
        best = Some(best.unwrap_or(0).max(number));
      }
    }
    start = at + needle.len();
  }
  best
}

fn is_pdf_whitespace(byte: u8) -> bool {
  matches!(byte, 0x00 | b'\t' | b'\n' | 0x0c | b'\r' | b' ')
}

fn is_pdf_name_byte(byte: u8) -> bool {
  !is_pdf_whitespace(byte)
    && !matches!(
      byte,
      b'(' | b')' | b'<' | b'>' | b'[' | b']' | b'{' | b'}' | b'/' | b'%'
    )
}

fn find_subslice(haystack: &[u8], needle: &[u8]) -> Option<usize> {
  if needle.is_empty() || haystack.len() < needle.len() {
    return None;
  }
  haystack.windows(needle.len()).position(|window| window == needle)
}

fn page_out_of_range(page: u32, page_count: u32) -> NotesError {
  NotesError::new(
    "page_out_of_range",
    format!("page {page} does not exist; the PDF has {page_count} page(s)"),
  )
}

fn page_unrendered(page: u32) -> NotesError {
  NotesError::new(
    "page_unrendered",
    format!("page {page} could not be rendered; use format original for the whole PDF"),
  )
}

fn single_image_page() -> NotesError {
  NotesError::new(
    "notes_error",
    "page applies only to a PDF or a scan; this attachment is a single image",
  )
}

fn page_not_applicable() -> NotesError {
  NotesError::new(
    "notes_error",
    "page applies only to a PDF, a scan, a photo, or a drawing",
  )
}

#[cfg(test)]
mod tests {
  use super::{component, file_uri, mime_type};
  use std::path::Path;

  #[test]
  fn refuses_components_that_leave_the_folder() {
    assert_eq!(component("Home inspection.jpeg"), Some("Home inspection.jpeg"));
    for bad in ["", ".", "..", "a/b", "../x", "a\0b"] {
      assert_eq!(component(bad), None, "{bad:?}");
    }
  }

  #[test]
  fn page_preview_covers_scans_and_pdfs() {
    assert!(super::page_preview(Some("com.apple.paper.doc.scan")));
    assert!(super::page_preview(Some("com.apple.paper.doc.pdf")));
    assert!(super::page_preview(Some("com.adobe.pdf")));
    assert!(!super::page_preview(Some("public.jpeg")));
    assert!(!super::page_preview(None));
  }

  #[test]
  fn names_mime_types_and_encodes_file_uris() {
    assert_eq!(mime_type(Path::new("/a/Scan.PDF")), "application/pdf");
    assert_eq!(mime_type(Path::new("/a/photo.HEIC")), "image/heic");
    assert_eq!(mime_type(Path::new("/a/blob")), "application/octet-stream");
    assert_eq!(file_uri(Path::new("/a b/ç.jpg")), "file:///a%20b/%C3%A7.jpg");
  }

  #[test]
  fn mime_type_follows_magic_bytes_when_the_extension_lies() {
    let dir = std::env::temp_dir().join(format!("abridge-mime-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("mime dir");
    let check = |name: &str, bytes: &[u8], mime: &str| {
      let path = dir.join(name);
      std::fs::write(&path, bytes).unwrap_or_else(|_| panic!("write {name}"));
      assert_eq!(mime_type(&path), mime, "{name}");
    };
    check("photo.jpeg", b"\xFF\xD8\xFFjpeg", "image/jpeg");
    check("photo.heic", b"\xFF\xD8\xFFjpeg", "image/jpeg");
    check("scan.jpg", b"%PDF-1.3", "application/pdf");
    check("icon.gif", b"\x89PNG\r\n\x1a\nrest", "image/png");
    check("anim.png", b"GIF89a", "image/gif");
    check("still.jpeg", b"RIFF\0\0\0\0WEBP", "image/webp");
    check("page.jpeg", b"II*\0tiff", "image/tiff");
    check("page.png", b"MM\0*tiff", "image/tiff");
    check("clip.jpeg", &ftyp(b"hevc"), "image/heif");
    check("clip.png", &ftyp(b"heic"), "image/heic");
    check("clip.gif", &ftyp(b"mif1"), "image/heif");
    check("clip.jpg", &ftyp(b"heix"), "image/heic");
    check("clip.heic", &ftyp(b"msf1"), "image/heif");
    check("movie.jpeg", &ftyp(b"qt  "), "video/quicktime");
    check("movie.png", &ftyp(b"isom"), "video/mp4");
    check("song.jpeg", &ftyp(b"M4A "), "audio/mp4");
    let _ = std::fs::remove_dir_all(&dir);
  }

  fn ftyp(brand: &[u8; 4]) -> Vec<u8> {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&16u32.to_be_bytes());
    bytes.extend_from_slice(b"ftyp");
    bytes.extend_from_slice(brand);
    bytes.extend_from_slice(&[0, 0, 0, 0]);
    bytes
  }

  #[test]
  fn export_rejects_a_symlinked_root() {
    let tmp = scratch_dir("root");
    let outside = tmp.join("outside");
    std::fs::create_dir(&outside).unwrap();
    let secret = outside.join("old.txt");
    std::fs::write(&secret, b"keep").unwrap();
    set_old(&secret);
    let mode_before = mode(&outside);
    let root = tmp.join("abridge-attachments");
    std::os::unix::fs::symlink(&outside, &root).unwrap();
    let source = tmp.join("photo.jpg");
    std::fs::write(&source, b"exported").unwrap();
    assert!(super::export_original_in(&root, "att", &source).is_err());
    assert_eq!(std::fs::read(&secret).unwrap(), b"keep");
    assert_eq!(mode(&outside), mode_before);
    assert!(std::fs::symlink_metadata(&root).unwrap().file_type().is_symlink());

    let file_root = tmp.join("not-a-dir");
    std::fs::write(&file_root, b"plain").unwrap();
    assert!(super::export_original_in(&file_root, "att", &source).is_err());
    assert_eq!(std::fs::read(&file_root).unwrap(), b"plain");
  }

  #[test]
  fn export_does_not_follow_a_child_symlink() {
    let tmp = scratch_dir("child");
    let outside = tmp.join("outside");
    std::fs::create_dir(&outside).unwrap();
    let secret = outside.join("secret");
    std::fs::write(&secret, b"keep").unwrap();
    set_old(&secret);
    let mode_before = mode(&outside);
    let root = tmp.join("root");
    std::fs::create_dir(&root).unwrap();
    std::os::unix::fs::symlink(&outside, root.join("link")).unwrap();
    let old = root.join("old");
    std::fs::create_dir(&old).unwrap();
    std::os::unix::fs::symlink(&secret, old.join("inner")).unwrap();
    set_old(&old);
    let source = tmp.join("photo.jpg");
    std::fs::write(&source, b"exported").unwrap();

    let exported = super::export_original_in(&root, "link", &source).unwrap();
    assert!(exported.starts_with(&root));
    assert!(!exported.starts_with(&outside));
    assert_eq!(std::fs::read(&exported).unwrap(), b"exported");
    assert!(!std::fs::symlink_metadata(&exported).unwrap().file_type().is_symlink());
    assert_eq!(std::fs::read(&secret).unwrap(), b"keep");
    assert_eq!(mode(&outside), mode_before);
    assert!(!old.exists());
  }

  #[test]
  fn export_replaces_a_destination_symlink_without_writing_its_target() {
    let tmp = scratch_dir("dest");
    let outside = tmp.join("outside");
    std::fs::create_dir(&outside).unwrap();
    let secret = outside.join("secret");
    std::fs::write(&secret, b"keep").unwrap();
    let root = tmp.join("root");
    let att = root.join("att");
    std::fs::create_dir_all(&att).unwrap();
    std::os::unix::fs::symlink(&secret, att.join("photo.jpg")).unwrap();
    let source = tmp.join("photo.jpg");
    std::fs::write(&source, b"exported").unwrap();

    let exported = super::export_original_in(&root, "att", &source).unwrap();
    assert_eq!(exported, att.join("photo.jpg"));
    assert_eq!(std::fs::read(&secret).unwrap(), b"keep");
    assert_eq!(std::fs::read(&exported).unwrap(), b"exported");
    assert!(std::fs::symlink_metadata(&exported).unwrap().file_type().is_file());
    assert_eq!(mode(&exported), 0o600);
    assert_eq!(mode(&root), 0o700);
    assert_eq!(mode(&att), 0o700);
  }

  #[test]
  fn extraction_does_not_read_a_sparse_file_over_the_cap() {
    let tmp = scratch_dir("sparse");
    let path = tmp.join("Accounts/acct/Media/media-1/big.pdf");
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    let file = std::fs::File::create(&path).unwrap();
    let oversized = 1 << 30;
    if file.set_len(oversized).is_err() {
      file.set_len(super::EXTRACTION_MAX_BYTES + 1).unwrap();
    }
    let row = uti_row("com.adobe.pdf");
    let err = super::markdown_from_file(&path, &row).unwrap_err();
    assert_eq!(err.code, "extraction_too_large");
    assert!(err.message.contains("50 MiB"));
    assert!(err.message.contains("not read"));
    assert!(indexed_text(&tmp, "big.pdf", "com.adobe.pdf").is_empty());
  }

  #[test]
  fn extraction_skips_an_unsupported_movie_and_a_fifo() {
    let tmp = scratch_dir("movie");
    let movie = tmp.join("clip.mov");
    let mut bytes = ftyp(b"qt  ");
    bytes.resize(64 * 1024, 0);
    std::fs::write(&movie, &bytes).unwrap();
    let row = uti_row("public.mpeg-4");
    assert_eq!(super::markdown_from_file(&movie, &row).unwrap(), super::ORIGINAL_HINT);

    let fifo = tmp.join("pipe.mov");
    let name = std::ffi::CString::new(fifo.to_str().unwrap()).unwrap();
    assert_eq!(unsafe { mkfifo(name.as_ptr(), 0o600) }, 0);
    assert_eq!(super::markdown_from_file(&fifo, &row).unwrap(), super::ORIGINAL_HINT);
  }

  #[test]
  fn extraction_reads_a_small_csv() {
    let tmp = scratch_dir("csv");
    let path = tmp.join("note.csv");
    std::fs::write(&path, "a,b\n1,2\n").unwrap();
    let text = super::markdown_from_file(&path, &uti_row("public.data")).unwrap();
    assert!(text.contains('1'), "{text}");
    assert!(!text.contains("original"));
  }

  fn scratch_dir(label: &str) -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!(
      "abridge-export-{label}-{}-{}",
      std::process::id(),
      std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
    ));
    std::fs::create_dir_all(&path).unwrap();
    path
  }

  fn set_old(path: &Path) {
    let file = std::fs::File::open(path).unwrap();
    let when = std::time::SystemTime::now() - std::time::Duration::from_secs(48 * 60 * 60);
    file.set_modified(when).unwrap();
  }

  fn mode(path: &Path) -> u32 {
    use std::os::unix::fs::PermissionsExt;
    std::fs::symlink_metadata(path).unwrap().permissions().mode() & 0o777
  }

  fn uti_row(uti: &str) -> super::store::EntityRow {
    let mut values = std::collections::HashMap::new();
    values.insert("typeUTI".to_string(), super::store::SqlValue::Text(uti.to_string()));
    super::store::EntityRow { pk: 1, values }
  }

  fn indexed_text(store_parent: &Path, file_name: &str, uti: &str) -> String {
    use super::store::{EntityRow, Snapshot, SqlValue};
    use std::collections::HashMap;
    fn row(pk: i64, ints: &[(&str, i64)], texts: &[(&str, &str)]) -> EntityRow {
      let mut values = HashMap::new();
      for (key, value) in ints {
        values.insert((*key).to_string(), SqlValue::Int(*value));
      }
      for (key, value) in texts {
        values.insert((*key).to_string(), SqlValue::Text((*value).to_string()));
      }
      EntityRow { pk, values }
    }
    let snap = Snapshot {
      uuid: None,
      accounts: vec![row(10, &[], &[("identifier", "acct")])],
      folders: vec![],
      notes: vec![row(1, &[("account", 10)], &[])],
      attachments: vec![row(
        2,
        &[("note", 1), ("media", 3)],
        &[("typeUTI", uti), ("identifier", "att")],
      )],
      inline_attachments: vec![],
      media: vec![row(3, &[], &[("identifier", "media-1"), ("filename", file_name)])],
      note_data: vec![],
    };
    super::indexed_document_text(
      store_parent.join("NoteStore.sqlite").as_path(),
      &snap,
      &snap.attachments[0],
    )
  }

  unsafe extern "C" {
    fn mkfifo(path: *const i8, mode: u32) -> i32;
  }
}

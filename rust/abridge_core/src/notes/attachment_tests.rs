use serde_json::{Value, json};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

use super::attachment_file::{self, plan_pages, recognize_pages};
use super::attachment_fixture::attachment_store;
use super::{NotesOutput, call_output, call_with_store};
use crate::config::{ProviderRequest, ProviderResponse};
use crate::providers::ProviderBridge;

/// `format` `original` writes `$TMPDIR/abridge-attachments`, which every test process shares.
/// The mutex covers threads in this process. The file lock covers other `cargo test` processes,
/// so one process cannot stat a copy another process is still writing.
struct OriginalLock {
  _thread: std::sync::MutexGuard<'static, ()>,
  file: std::fs::File,
}

fn original_lock() -> OriginalLock {
  static LOCK: Mutex<()> = Mutex::new(());
  let thread = LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
  let file = std::fs::OpenOptions::new()
    .create(true)
    .read(true)
    .write(true)
    .open(std::env::temp_dir().join("abridge-attachments.lock"))
    .expect("export lock");
  file.lock().expect("export lock");
  OriginalLock { _thread: thread, file }
}

impl Drop for OriginalLock {
  fn drop(&mut self) {
    let _ = self.file.unlock();
  }
}

fn mode_bits(path: &Path) -> u32 {
  std::fs::metadata(path).expect("metadata").permissions().mode() & 0o777
}

fn assert_original_export(output: &NotesOutput, identifier: &str, file_name: &str, source_suffix: &str) -> PathBuf {
  assert!(output.file.is_none(), "{identifier} inlined a blob");
  assert!(output.payload.get("rendition").is_none());
  let source = output.payload["source_path"].as_str().expect("source_path");
  assert!(source.ends_with(source_suffix), "{source}");
  let exported = PathBuf::from(output.payload["file_path"].as_str().expect("file_path"));
  let expected = std::env::temp_dir()
    .join("abridge-attachments")
    .join(identifier)
    .join(file_name);
  assert_eq!(exported, expected);
  assert_eq!(mode_bits(&exported), 0o600, "{identifier} file mode");
  assert_eq!(
    mode_bits(exported.parent().expect("dir")),
    0o700,
    "{identifier} dir mode"
  );
  assert_eq!(
    mode_bits(exported.parent().expect("dir").parent().expect("root")),
    0o700,
    "export root mode"
  );
  exported
}

fn get_attachment(store: &Path, identifier: &str) -> Result<NotesOutput, super::NotesError> {
  call_output(store, "get_attachment", &json!({ "attachment_identifier": identifier }))
}

fn get_attachment_as(store: &Path, identifier: &str, format: &str) -> Result<NotesOutput, super::NotesError> {
  call_output(
    store,
    "get_attachment",
    &json!({ "attachment_identifier": identifier, "format": format }),
  )
}

fn get_attachment_page(
  store: &Path,
  identifier: &str,
  max_characters: u64,
  offset: u64,
) -> Result<NotesOutput, super::NotesError> {
  call_output(
    store,
    "get_attachment",
    &json!({
      "attachment_identifier": identifier,
      "max_characters": max_characters,
      "offset": offset
    }),
  )
}

#[test]
fn reads_media_scan_and_drawing_files_from_the_account_folder() {
  let _export = original_lock();
  let (_dir, store) = attachment_store();
  let cases = [
    (
      "att-1",
      "jpeg bytes",
      "pic.jpg",
      "Accounts/acct-1/Media/media-1/pic.jpg",
    ),
    (
      "att-page",
      "page bytes",
      "Page 1.jpeg",
      "Accounts/acct-1/Media/media-2/1_GEN/Page 1.jpeg",
    ),
    (
      "att-scan",
      "%PDF scan",
      "FallbackPDF.pdf",
      "Accounts/acct-1/FallbackPDFs/att-scan/226_GEN/FallbackPDF.pdf",
    ),
    (
      "att-drawing",
      "png bytes",
      "att-drawing.png",
      "Accounts/acct-1/FallbackImages/att-drawing.png",
    ),
  ];
  for (identifier, bytes, file_name, source_suffix) in cases {
    let output =
      get_attachment_as(&store, identifier, "original").unwrap_or_else(|error| panic!("{identifier}: {error:?}"));
    assert_eq!(output.payload["identifier"], identifier);
    assert_eq!(output.payload["format"], "original");
    let exported = assert_original_export(&output, identifier, file_name, source_suffix);
    assert_eq!(
      std::fs::read(&exported).expect("export"),
      bytes.as_bytes(),
      "{identifier}"
    );
    let _ = std::fs::remove_dir_all(exported.parent().expect("dir"));
  }
}

#[test]
fn explains_why_an_attachment_has_no_readable_file() {
  let (_dir, store) = attachment_store();
  let code = |identifier: &str| match get_attachment(&store, identifier) {
    Ok(_) => "ok".to_string(),
    Err(error) => error.json()["code"].as_str().unwrap().to_string(),
  };
  assert_eq!(code("att-missing"), "attachment_file_unavailable");
  assert_eq!(code("att-locked"), "attachment_locked");
  assert_eq!(code("nope"), "not_found");

  let gallery = get_attachment(&store, "att-gallery").expect("gallery");
  assert_eq!(gallery.payload["format"], "markdown");
  assert_eq!(gallery.payload["kind"], "gallery");
  assert_eq!(gallery.payload["text_source"], "gallery");
  assert!(gallery.file.is_none());
  assert_eq!(gallery.payload["content"], "- [Page 1.jpeg](attachment:att-page)");
  let table = get_attachment(&store, "att-table").expect("table");
  assert_eq!(table.payload["text_source"], "table");
  assert!(table.file.is_none());
  assert!(table.payload["content"].as_str().unwrap().contains("| Right | Left |"));
  let no_file = |identifier: &str| match get_attachment_as(&store, identifier, "original") {
    Ok(_) => "ok".to_string(),
    Err(error) => error.json()["code"].as_str().unwrap().to_string(),
  };
  assert_eq!(no_file("att-gallery"), "attachment_has_no_file");
  assert_eq!(no_file("att-table"), "attachment_has_no_file");
}

#[test]
fn gallery_pages_and_inline_attachments_name_their_parent_attachment() {
  let (_dir, store) = attachment_store();
  let note = call_with_store(&store, "get_note", &json!({ "note_identifier": "note-i" })).expect("note");
  assert!(note.get("inline_attachments").is_none());
  let attachments = note["attachments"].as_array().unwrap();
  assert_eq!(attachments[0]["identifier"], "att-1");
  assert_eq!(attachments[0]["kind"], "photo");
  assert_eq!(attachments[1]["identifier"], "att-gallery");
  assert_eq!(attachments[1]["kind"], "gallery");
  let page = &attachments[1]["pages"][0];
  assert_eq!(page["identifier"], "att-page");
  assert_eq!(page["kind"], "photo");
  assert_eq!(page["type_uti"], "public.jpeg");
  assert_eq!(page["file_name"], "Page 1.jpeg");
  assert!(page.get("parent_identifier").is_none());
  assert!(page.get("parent_attachment").is_none());
  assert!(page.get("media").is_none());
  assert!(
    attachments
      .iter()
      .all(|attachment| attachment["identifier"] != "att-page")
  );
  let gallery = &attachments[1];
  assert_eq!(gallery["type_uti"], "com.apple.notes.gallery");
  assert!(gallery.get("parent_identifier").is_none());
  assert!(attachments.iter().any(|attachment| attachment["identifier"] == "att-1"));
  assert!(
    attachments
      .iter()
      .all(|attachment| attachment["identifier"] != "att-scan")
  );
  assert_eq!(note["attachment_count"], 2);

  let table_note = call_with_store(&store, "get_note", &json!({ "note_identifier": "note-j" })).expect("note");
  assert!(table_note.get("inline_attachments").is_none());
  assert!(table_note.get("attachments").is_none());
  assert!(table_note.get("attachment_count").is_none());
  assert!(table_note["body"].as_str().unwrap().contains("| Right | Left |"));

  let found = call_with_store(&store, "search_notes", &json!({ "query": "'#groceries" })).expect("search");
  let titles: Vec<&Value> = found.as_array().unwrap().iter().map(|n| &n["identifier"]).collect();
  assert_eq!(titles, vec!["note-i"]);
}

#[test]
fn a_heif_named_jpeg_is_not_labeled_jpeg_and_file_size_is_the_disk_length() {
  let (_dir, store) = attachment_store();
  let path = store.parent().unwrap().join("Accounts/acct-1/Media/media-1/pic.jpg");
  let mut bytes = Vec::new();
  bytes.extend_from_slice(&16u32.to_be_bytes());
  bytes.extend_from_slice(b"ftyphevc");
  bytes.extend_from_slice(&[0, 0, 0, 0]);
  std::fs::write(&path, &bytes).expect("heif");
  let conn = rusqlite::Connection::open(&store).expect("fixture db");
  conn
    .execute_batch("ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZFILESIZE INTEGER")
    .expect("filesize column");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZFILESIZE = 1, ZTYPEUTI = 'public.jpeg' WHERE ZIDENTIFIER = 'att-1'",
      [],
    )
    .expect("store size");

  let image = get_attachment_as(&store, "att-1", "image").expect("image");
  assert_eq!(image.payload["file_size"].as_u64(), Some(bytes.len() as u64));
  let file = image.file.expect("file");
  if file.mime_type == "image/jpeg" {
    assert!(
      file.bytes.starts_with(&[0xFF, 0xD8, 0xFF]),
      "HEIF bytes were labeled image/jpeg"
    );
    assert_eq!(image.payload["rendition"], "jpeg");
  } else {
    assert_eq!(file.mime_type, "image/heif");
    assert!(image.payload.get("rendition").is_none());
    assert!(file.bytes.windows(4).any(|chunk| chunk == b"ftyp"));
  }

  let markdown = get_attachment(&store, "att-1").expect("markdown");
  assert_eq!(markdown.payload["file_size"].as_u64(), Some(bytes.len() as u64));
  assert!(markdown.file.is_none());

  let note = call_with_store(&store, "get_note", &json!({ "note_identifier": "note-i" })).expect("note");
  let listed = note["attachments"]
    .as_array()
    .expect("attachments")
    .iter()
    .find(|attachment| attachment["identifier"] == "att-1")
    .expect("att-1");
  assert_eq!(listed["file_size"].as_u64(), Some(bytes.len() as u64));
}

#[test]
fn get_attachment_returns_the_full_deduped_ocr() {
  let (_dir, store) = attachment_store();
  let conn = rusqlite::Connection::open(&store).expect("fixture db");
  conn
    .execute_batch("ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZIMAGECLASSIFICATIONSUMMARY TEXT")
    .expect("classification column");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZOCRSUMMARY = ?1, ZSUMMARY = ?1, ZIMAGECLASSIFICATIONSUMMARY = 'a cat' \
       WHERE ZIDENTIFIER = 'att-1'",
      rusqlite::params!["Alpha line\tAlpha line\tBeta"],
    )
    .expect("ocr");
  let output = get_attachment(&store, "att-1").expect("attachment");
  assert_eq!(output.payload["format"], "markdown");
  assert_eq!(
    output.payload["content"],
    "Alpha line\nBeta\n\na cat\n\nThe image is available with format `image`."
  );
  assert_eq!(output.payload["description"], "a cat");
  assert_eq!(output.payload["kind"], "photo");
  assert_eq!(output.payload["text_source"], "saved");
  assert!(output.payload.get("text").is_none());
  assert!(output.payload.get("ocr_summary").is_none());
  assert!(output.payload.get("ocr_truncated").is_none());
  assert!(output.payload.get("image_classification_summary").is_none());
  assert!(output.payload.get("summary").is_none());
  assert!(output.payload.get("vision_available").is_none());
  assert!(output.payload.get("rendition").is_none());
  assert!(output.file.is_none());
  assert!(output.payload.get("file_path").is_none());
  assert!(
    output.payload["source_path"]
      .as_str()
      .unwrap()
      .ends_with("Accounts/acct-1/Media/media-1/pic.jpg")
  );
}

#[test]
fn image_and_original_omit_recognized_text_and_name_the_file() {
  let _export = original_lock();
  let (_dir, store) = attachment_store();
  let conn = rusqlite::Connection::open(&store).expect("fixture db");
  conn
    .execute_batch("ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZIMAGECLASSIFICATIONSUMMARY TEXT")
    .expect("classification column");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZOCRSUMMARY = ?1, ZSUMMARY = ?1, ZHANDWRITINGSUMMARY = 'ink', \
       ZIMAGECLASSIFICATIONSUMMARY = 'a cat' WHERE ZIDENTIFIER = 'att-1'",
      rusqlite::params!["Hello, world!\thello world"],
    )
    .expect("ocr");
  let image = get_attachment_as(&store, "att-1", "image").expect("image");
  assert_eq!(image.payload["format"], "image");
  assert!(image.file.is_some());
  assert!(image.payload.get("file_path").is_none());
  assert!(
    image.payload["source_path"]
      .as_str()
      .unwrap()
      .ends_with("Accounts/acct-1/Media/media-1/pic.jpg")
  );
  let original = get_attachment_as(&store, "att-1", "original").expect("original");
  assert_eq!(original.payload["format"], "original");
  let exported = assert_original_export(&original, "att-1", "pic.jpg", "Accounts/acct-1/Media/media-1/pic.jpg");
  assert_eq!(std::fs::read(&exported).expect("export"), b"jpeg bytes");
  for output in [&image, &original] {
    for key in [
      "ocr_summary",
      "ocr_truncated",
      "summary",
      "content",
      "text",
      "text_source",
      "text_truncated",
      "description",
      "handwriting",
      "handwriting_summary",
      "image_classification_summary",
      "additional_indexable_text",
      "vision_available",
    ] {
      assert!(
        output.payload.get(key).is_none(),
        "{} included {key}",
        output.payload["format"]
      );
    }
  }
  let _ = std::fs::remove_dir_all(exported.parent().expect("dir"));
}

#[test]
fn markdown_pages_content_and_collapses_near_duplicate_ocr() {
  let (_dir, store) = attachment_store();
  let conn = rusqlite::Connection::open(&store).expect("fixture db");
  let line = "Hello, world!";
  let raw = format!("{line}\thello world\tHELLO WORLD.");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZOCRSUMMARY = ?1 WHERE ZIDENTIFIER = 'att-scan'",
      rusqlite::params![raw],
    )
    .expect("ocr");
  let page = get_attachment_page(&store, "att-scan", 5, 0).expect("page");
  assert_eq!(page.payload["content"], "Hello");
  assert_eq!(page.payload["content_truncated"], true);
  assert_eq!(page.payload["next_offset"], 5);
  assert_eq!(page.payload["text_source"], "saved");
  assert_eq!(page.payload["kind"], "scan");
  assert!(page.payload.get("ocr_summary").is_none());
  assert!(page.payload.get("page_count").is_none());
  assert!(page.file.is_none());
  let rest = get_attachment_page(&store, "att-scan", 100, 5).expect("rest");
  assert_eq!(rest.payload["content"], ", world!");
  assert!(rest.payload.get("content_truncated").is_none());
  assert!(rest.payload.get("next_offset").is_none());
  let past = get_attachment_page(&store, "att-scan", 100, 100).expect("past");
  assert!(past.payload.get("content").is_none());
  assert!(past.payload.get("content_truncated").is_none());
  let invalid = call_output(
    &store,
    "get_attachment",
    &json!({ "attachment_identifier": "att-scan", "max_characters": 100001 }),
  )
  .unwrap_err();
  assert_eq!(invalid.json()["code"], "notes_error");
}

#[test]
fn original_copies_a_file_past_the_image_cap_without_a_blob() {
  let _export = original_lock();
  let (_dir, store) = attachment_store();
  let pdf = store
    .parent()
    .unwrap()
    .join("Accounts/acct-1/FallbackPDFs/att-scan/226_GEN/FallbackPDF.pdf");
  let len = crate::rendition::MAX_RESOURCE_BYTES + 1;
  std::fs::OpenOptions::new()
    .write(true)
    .open(&pdf)
    .expect("pdf")
    .set_len(len)
    .expect("len");
  let output = get_attachment_as(&store, "att-scan", "original").expect("original");
  let exported = assert_original_export(
    &output,
    "att-scan",
    "FallbackPDF.pdf",
    "Accounts/acct-1/FallbackPDFs/att-scan/226_GEN/FallbackPDF.pdf",
  );
  assert_eq!(std::fs::metadata(&exported).expect("export").len(), len);
  let _ = std::fs::remove_dir_all(exported.parent().expect("dir"));
  let markdown = get_attachment(&store, "att-scan").expect("scan text");
  assert_eq!(markdown.payload["format"], "markdown");
  assert!(markdown.file.is_none());
  assert!(markdown.payload.get("file_path").is_none());
  assert!(markdown.payload["content"].as_str().unwrap().contains("format `image`"));
}

#[test]
fn markdown_uses_deduped_ocr_for_a_scan_and_anydoc_for_a_csv() {
  let _export = original_lock();
  let (_dir, store) = attachment_store();
  let conn = rusqlite::Connection::open(&store).expect("fixture db");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZOCRSUMMARY = ?1 WHERE ZIDENTIFIER = 'att-scan'",
      rusqlite::params!["Line one\tLine one\tLine two"],
    )
    .expect("ocr");
  let scan = get_attachment(&store, "att-scan").expect("scan");
  assert_eq!(scan.payload["format"], "markdown");
  assert_eq!(scan.payload["content"], "Line one\nLine two");
  assert_eq!(scan.payload["text_source"], "saved");
  assert_eq!(scan.payload["kind"], "scan");
  assert!(scan.payload.get("ocr_summary").is_none());
  assert!(scan.file.is_none());

  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZFILENAME = 'notes.csv' WHERE ZIDENTIFIER = 'media-1'",
      [],
    )
    .expect("filename");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZTYPEUTI = 'public.comma-separated-values-text' WHERE ZIDENTIFIER = 'att-1'",
      [],
    )
    .expect("uti");
  let csv = store.parent().unwrap().join("Accounts/acct-1/Media/media-1/notes.csv");
  std::fs::write(&csv, b"Name,Qty\nApples,2\n").expect("csv");
  let document = get_attachment(&store, "att-1").expect("csv");
  assert_eq!(document.payload["format"], "markdown");
  assert!(document.file.is_none());
  assert!(document.payload["content"].as_str().unwrap().contains("Apples"));
  assert_eq!(document.payload["text_source"], "document");
  assert_eq!(document.payload["kind"], "document");
  assert!(document.payload.get("page_count").is_none());
  let image = match get_attachment_as(&store, "att-1", "image") {
    Ok(_) => panic!("a csv is not an image"),
    Err(error) => error,
  };
  assert_eq!(image.json()["code"], "attachment_not_viewable");
  let original = get_attachment_as(&store, "att-1", "original").expect("original");
  let exported = assert_original_export(
    &original,
    "att-1",
    "notes.csv",
    "Accounts/acct-1/Media/media-1/notes.csv",
  );
  assert_eq!(std::fs::read(&exported).expect("export"), b"Name,Qty\nApples,2\n");
  let _ = std::fs::remove_dir_all(exported.parent().expect("dir"));
}

#[test]
fn original_ages_out_export_entries_older_than_a_day() {
  let _export = original_lock();
  let root = std::env::temp_dir().join("abridge-attachments");
  let stale = root.join("stale-id");
  let fresh = root.join("fresh-id");
  std::fs::create_dir_all(&stale).expect("stale");
  std::fs::create_dir_all(&fresh).expect("fresh");
  std::fs::write(stale.join("old.bin"), b"old").expect("old");
  std::fs::write(fresh.join("new.bin"), b"new").expect("new");
  let ancient = SystemTime::now() - Duration::from_secs(25 * 60 * 60);
  std::fs::File::open(&stale)
    .expect("stale dir")
    .set_modified(ancient)
    .expect("mtime");

  let (_dir, store) = attachment_store();
  let output = get_attachment_as(&store, "att-1", "original").expect("original");
  let exported = assert_original_export(&output, "att-1", "pic.jpg", "Accounts/acct-1/Media/media-1/pic.jpg");
  assert!(!stale.exists(), "an export older than 24 hours was kept");
  assert_eq!(std::fs::read(fresh.join("new.bin")).expect("fresh"), b"new");
  let _ = std::fs::remove_dir_all(exported.parent().expect("dir"));
  let _ = std::fs::remove_dir_all(fresh);
}

/// `sips` renders the requested page of a generated PDF, and a non-model image is marked as a JPEG
/// rendition. Page 1 is square and page 2 is wide, so the JPEG's shape shows which page came back.
#[cfg(target_os = "macos")]
#[test]
fn renders_a_pdf_page_and_marks_a_scaled_photo() {
  let (_dir, store) = attachment_store();
  let root = store.parent().unwrap();
  let pdf = root.join("Accounts/acct-1/FallbackPDFs/att-scan/226_GEN/FallbackPDF.pdf");
  std::fs::write(&pdf, pdf_with_pages(&[(200, 200), (300, 100)])).expect("pdf");
  let scan = get_attachment_as(&store, "att-scan", "image").expect("scan");
  assert_eq!(scan.payload["format"], "image");
  assert_eq!(scan.payload["rendition"], "jpeg_page");
  assert_eq!(scan.payload["page"], 1);
  assert_eq!(scan.payload["page_count"], 2);
  assert_eq!(scan.payload["type_uti"], "com.apple.paper.doc.scan");
  let file = scan.file.expect("jpeg");
  assert_eq!(file.mime_type, "image/jpeg");
  let (width, height) = jpeg_size(&file.bytes);
  assert_eq!(width, height, "page 1 is square");

  let second = call_output(
    &store,
    "get_attachment",
    &json!({ "attachment_identifier": "att-scan", "format": "image", "page": 2 }),
  )
  .expect("page 2");
  assert_eq!(second.payload["page"], 2);
  assert_eq!(second.payload["page_count"], 2);
  let (width, height) = jpeg_size(&second.file.expect("jpeg").bytes);
  assert!(width > height * 2, "page 2 is wide: {width}x{height}");

  let past = call_output(
    &store,
    "get_attachment",
    &json!({ "attachment_identifier": "att-scan", "format": "image", "page": 3 }),
  )
  .expect_err("past the end");
  assert_eq!(past.code, "page_out_of_range");
  assert!(past.message.contains("2 page"), "{}", past.message);

  let conn = rusqlite::Connection::open(&store).expect("fixture db");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZFILENAME = 'pic.bmp' WHERE ZIDENTIFIER = 'media-1'",
      [],
    )
    .expect("filename");
  std::fs::write(root.join("Accounts/acct-1/Media/media-1/pic.bmp"), tiny_bmp()).expect("bmp");
  let photo = get_attachment_as(&store, "att-1", "image").expect("photo");
  assert_eq!(photo.payload["format"], "image");
  assert_eq!(photo.payload["rendition"], "jpeg");
  let photo_file = photo.file.expect("jpeg");
  assert_eq!(photo_file.mime_type, "image/jpeg");
  assert!(photo_file.bytes.starts_with(&[0xff, 0xd8, 0xff]));
}

/// Width and height from a JPEG's start-of-frame marker.
#[cfg(target_os = "macos")]
fn jpeg_size(jpeg: &[u8]) -> (u32, u32) {
  assert!(jpeg.starts_with(&[0xff, 0xd8, 0xff]), "not a JPEG");
  let mut at = 2;
  while at + 9 < jpeg.len() {
    let marker = jpeg[at + 1];
    let length = usize::from(u16::from_be_bytes([jpeg[at + 2], jpeg[at + 3]]));
    if matches!(marker, 0xc0..=0xc3) {
      let height = u32::from(u16::from_be_bytes([jpeg[at + 5], jpeg[at + 6]]));
      let width = u32::from(u16::from_be_bytes([jpeg[at + 7], jpeg[at + 8]]));
      return (width, height);
    }
    at += 2 + length;
  }
  panic!("no start-of-frame marker");
}

/// A PDF with one filled page per `(width, height)` media box.
fn pdf_with_pages(sizes: &[(u32, u32)]) -> Vec<u8> {
  let stream = b"1 0 0 rg 20 20 60 60 re f\n";
  let kids: Vec<String> = (0..sizes.len()).map(|index| format!("{} 0 R", 3 + 2 * index)).collect();
  let mut objects: Vec<Vec<u8>> = vec![
    b"<< /Type /Catalog /Pages 2 0 R >>".to_vec(),
    format!("<< /Type /Pages /Count {} /Kids [{}] >>", sizes.len(), kids.join(" ")).into_bytes(),
  ];
  for (index, (width, height)) in sizes.iter().enumerate() {
    objects.push(
      format!(
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width} {height}] /Contents {} 0 R >>",
        4 + 2 * index
      )
      .into_bytes(),
    );
    let mut contents = format!("<< /Length {} >>\nstream\n", stream.len()).into_bytes();
    contents.extend_from_slice(stream);
    contents.extend_from_slice(b"endstream");
    objects.push(contents);
  }
  let mut out = Vec::from(&b"%PDF-1.4\n"[..]);
  let mut offsets = Vec::with_capacity(objects.len());
  for (index, object) in objects.iter().enumerate() {
    offsets.push(out.len());
    out.extend(format!("{} 0 obj\n", index + 1).bytes());
    out.extend_from_slice(object);
    out.extend_from_slice(b"\nendobj\n");
  }
  let xref = out.len();
  out.extend(format!("xref\n0 {}\n", objects.len() + 1).bytes());
  out.extend_from_slice(b"0000000000 65535 f \n");
  for offset in offsets {
    out.extend(format!("{offset:010} 00000 n \n").bytes());
  }
  out.extend(
    format!(
      "trailer<</Size {}/Root 1 0 R>>\nstartxref\n{xref}\n%%EOF\n",
      objects.len() + 1
    )
    .bytes(),
  );
  out
}

#[cfg(target_os = "macos")]
fn tiny_bmp() -> Vec<u8> {
  let width = 8u32;
  let height = 8u32;
  let row = (width * 3).div_ceil(4) * 4;
  let pixels = row * height;
  let mut bytes = Vec::new();
  bytes.extend_from_slice(b"BM");
  for value in [54 + pixels, 0, 54, 40] {
    bytes.extend_from_slice(&value.to_le_bytes());
  }
  bytes.extend_from_slice(&(width as i32).to_le_bytes());
  bytes.extend_from_slice(&(height as i32).to_le_bytes());
  bytes.extend_from_slice(&1u16.to_le_bytes());
  bytes.extend_from_slice(&24u16.to_le_bytes());
  for value in [0u32, pixels, 2835, 2835, 0, 0] {
    bytes.extend_from_slice(&value.to_le_bytes());
  }
  bytes.resize(54 + pixels as usize, 0x7f);
  bytes
}

#[test]
fn page_is_only_for_image_and_multi_page_files() {
  let (_dir, store) = attachment_store();
  let markdown = call_output(
    &store,
    "get_attachment",
    &json!({ "attachment_identifier": "att-scan", "page": 2 }),
  )
  .expect_err("page 2 of an unreadable scan");
  assert_eq!(markdown.code, "page_unrendered");

  let photo = call_output(
    &store,
    "get_attachment",
    &json!({ "attachment_identifier": "att-1", "page": 2 }),
  )
  .expect_err("page 2 of a photo");
  assert!(photo.message.contains("single image"), "{}", photo.message);

  let image = call_output(
    &store,
    "get_attachment",
    &json!({ "attachment_identifier": "att-1", "format": "image", "page": 2 }),
  )
  .expect_err("page 2 of a photo image");
  assert!(image.message.contains("single image"), "{}", image.message);

  let gallery = call_output(
    &store,
    "get_attachment",
    &json!({ "attachment_identifier": "att-gallery", "page": 1 }),
  )
  .expect_err("page of a gallery");
  assert!(gallery.message.contains("PDF, a scan"), "{}", gallery.message);
}

struct VisionScript {
  texts: Vec<&'static str>,
  fail: bool,
  calls: Mutex<Vec<ProviderRequest>>,
}

impl VisionScript {
  fn ok(texts: Vec<&'static str>) -> Self {
    Self {
      texts,
      fail: false,
      calls: Mutex::new(Vec::new()),
    }
  }

  fn failing() -> Self {
    Self {
      texts: Vec::new(),
      fail: true,
      calls: Mutex::new(Vec::new()),
    }
  }

  fn calls(&self) -> Vec<ProviderRequest> {
    self
      .calls
      .lock()
      .unwrap_or_else(|poisoned| poisoned.into_inner())
      .clone()
  }
}

impl ProviderBridge for VisionScript {
  fn call_provider(&self, request: ProviderRequest) -> ProviderResponse {
    let index = {
      let mut calls = self.calls.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
      let index = calls.len();
      calls.push(request);
      index
    };
    if self.fail {
      return ProviderResponse {
        ok: false,
        payload_json: "{}".into(),
        error_json: Some(r#"{"code":"vision_error","message":"vision failed"}"#.into()),
      };
    }
    let text = self
      .texts
      .get(index)
      .copied()
      .or_else(|| self.texts.last().copied())
      .unwrap_or("");
    ProviderResponse {
      ok: true,
      payload_json: json!({
        "results": [{ "candidates": [{ "string": text }] }]
      })
      .to_string(),
      error_json: None,
    }
  }
}

fn assert_vision_request(request: &ProviderRequest, image: &[u8]) {
  assert_eq!(request.provider, "vision");
  assert_eq!(request.operation, "recognize_text");
  let payload: Value = serde_json::from_str(&request.payload_json).expect("payload");
  assert!(payload.get("image_path").is_none());
  assert!(payload.get("page").is_none());
  let encoded = payload["image_data"].as_str().expect("image_data");
  let decoded = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded).expect("base64");
  assert_eq!(decoded, image);
}

fn assert_one_page_pdf(request: &ProviderRequest) -> Vec<u8> {
  assert_eq!(request.provider, "vision");
  assert_eq!(request.operation, "recognize_text");
  let payload: Value = serde_json::from_str(&request.payload_json).expect("payload");
  assert!(payload.get("image_path").is_none());
  assert!(payload.get("page").is_none());
  let encoded = payload["image_data"].as_str().expect("image_data");
  let decoded = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded).expect("base64");
  assert!(decoded.starts_with(b"%PDF"), "image_data is not a PDF");
  let document = lopdf::Document::load_mem(&decoded).expect("one-page pdf");
  assert_eq!(document.get_pages().len(), 1);
  decoded
}

#[test]
fn vision_markdown_sections_one_page_and_a_chosen_page() {
  let both = VisionScript::ok(vec!["Alpha line", "Beta line"]);
  let pages = [(1, b"page-one".to_vec()), (2, b"page-two".to_vec())];
  let content = recognize_pages(&pages, &both).expect("markdown");
  assert_eq!(content, "## Page 1\n\nAlpha line\n\n## Page 2\n\nBeta line");
  let calls = both.calls();
  assert_eq!(calls.len(), 2);
  assert_vision_request(&calls[0], b"page-one");
  assert_vision_request(&calls[1], b"page-two");

  let one = VisionScript::ok(vec!["Only line"]);
  let single = recognize_pages(&[(1, b"solo".to_vec())], &one).expect("one page");
  assert_eq!(single, "Only line");
  assert!(!single.contains("## Page"));

  let plan = plan_pages(4, Some(2)).expect("page 2");
  assert_eq!(plan.numbers, vec![2]);
  assert!(!plan.truncated);
  let chosen = VisionScript::ok(vec!["Second page"]);
  let page = recognize_pages(&[(2, b"second".to_vec())], &chosen).expect("page");
  assert_eq!(page, "Second page");
  assert_vision_request(&chosen.calls()[0], b"second");
  let past = plan_pages(4, Some(5)).unwrap_err();
  assert_eq!(past.code, "page_out_of_range");
}

#[test]
fn vision_stops_after_twenty_pages() {
  let plan = plan_pages(25, None).expect("plan");
  assert!(plan.truncated);
  assert_eq!(plan.next_page, Some(21));
  assert_eq!(plan.numbers, (1..=20).collect::<Vec<_>>());
  let texts: Vec<&str> = [
    "p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8", "p9", "p10", "p11", "p12", "p13", "p14", "p15", "p16", "p17",
    "p18", "p19", "p20",
  ]
  .to_vec();
  let bridge = VisionScript::ok(texts);
  let pages: Vec<(u32, Vec<u8>)> = plan
    .numbers
    .iter()
    .map(|number| (*number, vec![*number as u8]))
    .collect();
  let content = recognize_pages(&pages, &bridge).expect("capped");
  assert!(content.starts_with("## Page 1\n\np1"), "{content}");
  assert!(content.contains("## Page 20\n\np20"), "{content}");
  assert!(!content.contains("## Page 21"));
  assert_eq!(bridge.calls().len(), 20);
  assert!(plan_pages(20, None).expect("exact").next_page.is_none());
}

#[test]
fn vision_disabled_or_failing_uses_stored_ocr() {
  let (_dir, store) = attachment_store();
  let conn = rusqlite::Connection::open(&store).expect("fixture db");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZOCRSUMMARY = ?1 WHERE ZIDENTIFIER = 'att-scan'",
      rusqlite::params!["Scan line\tScan line"],
    )
    .expect("ocr");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZOCRSUMMARY = 'Photo line' WHERE ZIDENTIFIER = 'att-1'",
      [],
    )
    .expect("photo ocr");

  let disabled = VisionScript::failing();
  let scan = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-scan" }),
    Some(&disabled),
    false,
  )
  .expect("scan");
  assert_eq!(scan.payload["content"], "Scan line");
  assert_eq!(scan.payload["text_source"], "saved");
  assert!(disabled.calls().is_empty());
  assert!(scan.payload.get("pages_truncated").is_none());
  assert!(scan.payload.get("vision_available").is_none());

  let failing = VisionScript::failing();
  let photo = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "text_source": "vision" }),
    Some(&failing),
    true,
  )
  .expect_err("vision failure");
  assert_eq!(photo.code, "vision_failed");
  assert_eq!(
    photo.message,
    "Vision did not return text: vision failed. View it with format image."
  );
  assert!(!photo.message.contains("Photo line"));
  assert_eq!(failing.calls().len(), 1);
  assert_eq!(failing.calls()[0].operation, "recognize_text");
  assert_vision_request(&failing.calls()[0], b"jpeg bytes");

  let unavailable = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "text_source": "vision" }),
    Some(&failing),
    false,
  )
  .expect_err("vision disabled");
  assert_eq!(unavailable.code, "vision_unavailable");
  assert_eq!(failing.calls().len(), 1);

  let empty = VisionScript::ok(vec![""]);
  let blank = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "text_source": "vision" }),
    Some(&empty),
    true,
  )
  .expect_err("empty vision");
  assert_eq!(blank.code, "vision_failed");
  assert_eq!(blank.message, "Vision did not return text. View it with format image.");
  assert!(!blank.message.contains("vision failed"));
}

#[test]
fn vision_failure_on_a_scan_names_the_page_to_view() {
  let (_dir, store) = attachment_store();
  let pdf = scan_pdf(&store);
  std::fs::write(&pdf, pdf_with_pages(&[(20, 40), (40, 20)])).expect("pdf");
  let failing = VisionScript::failing();
  let scan = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-scan", "text_source": "vision" }),
    Some(&failing),
    true,
  )
  .expect_err("scan vision");
  assert_eq!(scan.code, "vision_failed");
  assert_eq!(
    scan.message,
    "Vision did not return text: vision failed. View it with format image (page 1 of 2)."
  );
  assert!(!failing.calls().is_empty());
}

#[test]
fn automatic_vision_failure_does_not_claim_saved_text() {
  let (_dir, store) = attachment_store();
  let conn = rusqlite::Connection::open(&store).expect("fixture db");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT
       SET ZOCRSUMMARY = NULL, ZSUMMARY = NULL, ZHANDWRITINGSUMMARY = NULL
       WHERE ZIDENTIFIER IN ('att-1', 'att-scan')",
      [],
    )
    .expect("clear saved text");
  drop(conn);
  std::fs::write(scan_pdf(&store), pdf_with_pages(&[(20, 40), (40, 20)])).expect("pdf");

  let photo_bridge = VisionScript::failing();
  let photo = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1" }),
    Some(&photo_bridge),
    true,
  )
  .expect("automatic photo");
  assert_eq!(photo.payload["text_source"], "vision");
  assert_eq!(
    photo.payload["content"],
    "Vision was tried and could not read it: vision failed. View it with format image."
  );
  assert!(photo.payload.get("page_count").is_none());
  assert_eq!(photo_bridge.calls().len(), 1);

  let scan_bridge = VisionScript::failing();
  let scan = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-scan" }),
    Some(&scan_bridge),
    true,
  )
  .expect("automatic scan");
  assert_eq!(scan.payload["text_source"], "vision");
  assert_eq!(
    scan.payload["content"],
    "Vision was tried and could not read it: vision failed. View it with format image (page 1 of 2)."
  );
  assert_eq!(scan.payload["page_count"], 2);
  assert!(!scan_bridge.calls().is_empty());
}

#[test]
fn vision_reads_a_photo_and_markdown_still_pages_characters() {
  let (_dir, store) = attachment_store();
  let bridge = VisionScript::ok(vec!["Alphabet"]);
  let output = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "text_source": "vision" }),
    Some(&bridge),
    true,
  )
  .expect("vision");
  assert_eq!(output.payload["content"], "Alphabet");
  assert_eq!(output.payload["text_source"], "vision");
  assert_eq!(output.payload["format"], "markdown");
  assert!(output.payload.get("vision_available").is_none());
  assert!(output.file.is_none());
  assert_vision_request(&bridge.calls()[0], b"jpeg bytes");

  let paged = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "text_source": "vision", "max_characters": 4, "offset": 0 }),
    Some(&bridge),
    true,
  )
  .expect("page");
  assert_eq!(paged.payload["content"], "Alph");
  assert_eq!(paged.payload["content_truncated"], true);
  assert_eq!(paged.payload["next_offset"], 4);
  assert_eq!(paged.payload["text_source"], "vision");
}

#[test]
fn vision_sends_each_scan_page_as_a_one_page_pdf() {
  let (_dir, store) = attachment_store();
  let pdf = store
    .parent()
    .unwrap()
    .join("Accounts/acct-1/FallbackPDFs/att-scan/226_GEN/FallbackPDF.pdf");
  std::fs::write(&pdf, pdf_with_pages(&[(20, 40), (40, 20)])).expect("pdf");
  let bridge = VisionScript::ok(vec!["Receipt total", "Second page"]);
  let output = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-scan", "text_source": "vision" }),
    Some(&bridge),
    true,
  )
  .expect("scan");
  assert_eq!(
    output.payload["content"],
    "## Page 1\n\nReceipt total\n\n## Page 2\n\nSecond page"
  );
  assert_eq!(output.payload["text_source"], "vision");
  assert_eq!(output.payload["page_count"], 2);
  assert!(output.payload.get("page").is_none());
  let calls = bridge.calls();
  assert_eq!(calls.len(), 2);
  let first = assert_one_page_pdf(&calls[0]);
  let second = assert_one_page_pdf(&calls[1]);
  assert_ne!(first, second);

  let page = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-scan", "page": 2 }),
    Some(&bridge),
    true,
  )
  .expect("page 2");
  assert_eq!(page.payload["content"], "Second page");
  assert_eq!(page.payload["text_source"], "vision");
  assert_eq!(page.payload["page"], 2);
  assert_eq!(page.payload["page_count"], 2);
  assert!(!page.payload["content"].as_str().unwrap().contains("## Page"));
  assert_one_page_pdf(&bridge.calls()[2]);
}

#[test]
fn ocr_defaults_to_saved_text_and_page_implies_vision() {
  let (_dir, store) = attachment_store();
  let conn = rusqlite::Connection::open(&store).expect("fixture db");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZOCRSUMMARY = 'alpha beta gamma delta' WHERE ZIDENTIFIER = 'att-1'",
      [],
    )
    .expect("ocr");
  let bridge = VisionScript::ok(vec!["tiny"]);

  let saved = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1" }),
    Some(&bridge),
    true,
  )
  .expect("default");
  assert_eq!(
    saved.payload["content"],
    "alpha beta gamma delta\n\nThe image is available with format `image`."
  );
  assert_eq!(saved.payload["text_source"], "saved");
  assert_eq!(saved.payload["kind"], "photo");
  assert!(saved.payload.get("vision_available").is_none());
  assert!(bridge.calls().is_empty());

  let explicit_saved = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "text_source": "saved" }),
    Some(&bridge),
    true,
  )
  .expect("explicit saved");
  assert_eq!(explicit_saved.payload["text_source"], "saved");
  assert!(bridge.calls().is_empty());

  let disabled = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1" }),
    Some(&bridge),
    false,
  )
  .expect("vision off");
  assert!(disabled.payload.get("vision_available").is_none());
  assert!(bridge.calls().is_empty());

  let explicit = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "text_source": "vision" }),
    Some(&bridge),
    true,
  )
  .expect("explicit vision");
  assert_eq!(explicit.payload["content"], "tiny");
  assert_eq!(explicit.payload["text_source"], "vision");
  assert!(explicit.payload.get("vision_available").is_none());
  assert_vision_request(&bridge.calls()[0], b"jpeg bytes");

  let implied = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "page": 1 }),
    Some(&bridge),
    true,
  )
  .expect("page implies vision");
  assert_eq!(implied.payload["content"], "tiny");
  assert_eq!(implied.payload["text_source"], "vision");
  assert_eq!(bridge.calls().len(), 2);

  let notes_page = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "text_source": "saved", "page": 1 }),
    Some(&bridge),
    true,
  )
  .expect_err("saved with page");
  assert_eq!(notes_page.code, "invalid_arguments");
  assert!(
    notes_page.message.contains("text_source saved"),
    "{}",
    notes_page.message
  );

  let image = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "format": "image", "text_source": "vision" }),
    Some(&bridge),
    true,
  )
  .expect_err("ocr on image");
  assert_eq!(image.code, "invalid_arguments");
  assert!(image.message.contains("markdown"), "{}", image.message);

  let original = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "format": "original", "text_source": "saved" }),
    Some(&bridge),
    true,
  )
  .expect_err("ocr on original");
  assert_eq!(original.code, "invalid_arguments");
  assert_eq!(bridge.calls().len(), 2);
}

#[test]
fn saved_is_the_default_and_vision_runs_when_nothing_is_saved() {
  let (_dir, store) = attachment_store();
  let conn = rusqlite::Connection::open(&store).expect("db");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT
       SET ZOCRSUMMARY = NULL, ZSUMMARY = NULL, ZHANDWRITINGSUMMARY = NULL
       WHERE ZIDENTIFIER = 'att-1'",
      [],
    )
    .expect("clear saved text");
  drop(conn);
  let bridge = VisionScript::ok(vec!["Seen"]);
  let empty = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1" }),
    Some(&bridge),
    true,
  )
  .expect("automatic vision");
  assert_eq!(empty.payload["content"], "Seen");
  assert_eq!(empty.payload["text_source"], "vision");
  assert_eq!(bridge.calls().len(), 1);

  let held = VisionScript::ok(vec!["Should not run"]);
  let saved = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "text_source": "saved" }),
    Some(&held),
    true,
  )
  .expect("explicit saved");
  assert_eq!(saved.payload["content"], "The image is available with format `image`.");
  assert_eq!(saved.payload["text_source"], "saved");
  assert!(held.calls().is_empty());

  let removed = attachment_file::get_attachment(
    &store,
    &json!({ "attachment_identifier": "att-1", "ocr": "vision" }),
    Some(&held),
    true,
  )
  .expect_err("ocr removed");
  assert_eq!(removed.code, "invalid_arguments");
  assert!(held.calls().is_empty());
}

#[test]
fn page_count_byte_scan_uses_the_root_of_a_nested_page_tree() {
  let (_dir, store) = attachment_store();
  let pdf = scan_pdf(&store);
  let mut bytes = Vec::from(&b"%PDF-1.4\n%"[..]);
  bytes.extend(std::iter::repeat(b'x').take(70_000));
  bytes.extend(b"\n/Count 99\n");
  let objects: [&[u8]; 6] = [
    b"<< /Type /Catalog /Pages 2 0 R >>",
    b"<< /Count 3\n/Type\n/Pages\n/Kids [3 0 R 4 0 R] >>",
    b"<< /Type /Pages\n/Parent 2 0 R\n/Count 2\n/Kids [5 0 R 6 0 R] >>",
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] >>",
    b"<< /Type /Page /Parent 3 0 R /MediaBox [0 0 10 10] >>",
    b"<< /Type /Page /Parent 3 0 R /MediaBox [0 0 10 10] >>",
  ];
  for (index, object) in objects.iter().enumerate() {
    bytes.extend(format!("{} 0 obj\n", index + 1).bytes());
    bytes.extend_from_slice(object);
    bytes.extend(b"\nendobj\n");
  }
  bytes.extend(b"trailer\n<< /Root 1 0 R >>\n%%EOF\n");
  std::fs::write(&pdf, &bytes).expect("nested pdf");

  let snap = super::store::load(&store).expect("snap");
  let row = super::store::row_by_identifier(&snap.attachments, "att-scan").expect("row");
  assert_eq!(super::attachment_file::page_count(&store, &snap, row), Some(3));
}

#[test]
fn page_count_cache_reuses_a_count_for_the_same_path_size_and_mtime() {
  let (_dir, store) = attachment_store();
  let pdf = scan_pdf(&store);
  let mut two = pdf_with_pages(&[(10, 10), (12, 12)]);
  let mut five = pdf_with_pages(&[(10, 10), (11, 11), (12, 12), (13, 13), (14, 14)]);
  let len = two.len().max(five.len());
  two.resize(len, b'\n');
  five.resize(len, b'\n');
  std::fs::write(&pdf, &two).expect("two pages");
  let stamp = SystemTime::UNIX_EPOCH + Duration::from_secs(1_700_000_000);
  std::fs::File::options()
    .write(true)
    .open(&pdf)
    .expect("touch")
    .set_modified(stamp)
    .expect("mtime");

  let snap = super::store::load(&store).expect("snap");
  let row = super::store::row_by_identifier(&snap.attachments, "att-scan").expect("row");
  assert_eq!(super::attachment_file::page_count(&store, &snap, row), Some(2));

  std::fs::write(&pdf, &five).expect("five pages");
  std::fs::File::options()
    .write(true)
    .open(&pdf)
    .expect("touch")
    .set_modified(stamp)
    .expect("mtime");
  assert_eq!(
    std::fs::metadata(&pdf).expect("meta").len(),
    len as u64,
    "cache key length changed"
  );
  assert_eq!(super::attachment_file::page_count(&store, &snap, row), Some(2));

  std::fs::File::options()
    .write(true)
    .open(&pdf)
    .expect("touch")
    .set_modified(stamp + Duration::from_secs(10))
    .expect("new mtime");
  assert_eq!(super::attachment_file::page_count(&store, &snap, row), Some(5));
}

#[test]
fn page_count_uses_lopdf_when_a_small_page_tree_is_in_an_object_stream() {
  let (_dir, store) = attachment_store();
  let plain = pdf_with_pages(&[(10, 10), (12, 12)]);
  let mut document = lopdf::Document::load_mem(&plain).expect("plain pdf");
  let mut compressed = Vec::new();
  document
    .save_with_options(
      &mut compressed,
      lopdf::SaveOptions::builder()
        .use_object_streams(true)
        .compression_level(6)
        .build(),
    )
    .expect("object streams");
  assert!(
    !compressed
      .windows(b"/Type /Pages".len())
      .any(|window| window == b"/Type /Pages")
      && !compressed
        .windows(b"/Type/Pages".len())
        .any(|window| window == b"/Type/Pages"),
    "object stream still left a plaintext page tree"
  );
  assert!(compressed.len() as u64 <= 4 * 1024 * 1024);
  let pdf = scan_pdf(&store);
  std::fs::write(&pdf, &compressed).expect("compressed pdf");
  let snap = super::store::load(&store).expect("snap");
  let row = super::store::row_by_identifier(&snap.attachments, "att-scan").expect("row");
  assert_eq!(super::attachment_file::page_count(&store, &snap, row), Some(2));
}

fn scan_pdf(store: &Path) -> PathBuf {
  store
    .parent()
    .unwrap()
    .join("Accounts/acct-1/FallbackPDFs/att-scan/226_GEN/FallbackPDF.pdf")
}

#[test]
fn page_count_is_present_for_a_counted_scan_and_omitted_otherwise() {
  let (_dir, store) = attachment_store();
  let pdf = store
    .parent()
    .unwrap()
    .join("Accounts/acct-1/FallbackPDFs/att-scan/226_GEN/FallbackPDF.pdf");
  std::fs::write(&pdf, pdf_with_pages(&[(10, 10), (12, 12)])).expect("pdf");
  let scan = get_attachment(&store, "att-scan").expect("scan");
  assert_eq!(scan.payload["kind"], "scan");
  assert_eq!(scan.payload["page_count"], 2);
  assert_eq!(scan.payload["text_source"], "saved");

  let photo = get_attachment(&store, "att-1").expect("photo");
  assert_eq!(photo.payload["kind"], "photo");
  assert!(photo.payload.get("page_count").is_none());

  std::fs::write(&pdf, b"%PDF-1.4\n/Count 1\n").expect("guess");
  let omitted = get_attachment(&store, "att-scan").expect("unparsed");
  assert!(omitted.payload.get("page_count").is_none(), "{}", omitted.payload);
}

#[test]
fn attachment_kind_covers_documents_drawings_and_text_pdfs() {
  let (_dir, store) = attachment_store();
  let drawing = get_attachment(&store, "att-drawing").expect("drawing");
  assert_eq!(drawing.payload["kind"], "drawing");
  assert_eq!(drawing.payload["text_source"], "saved");

  let conn = rusqlite::Connection::open(&store).expect("db");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZTYPEUTI = 'public.mp3' WHERE ZIDENTIFIER = 'att-1'",
      [],
    )
    .expect("audio uti");
  drop(conn);
  let audio = get_attachment(&store, "att-1").expect("audio");
  assert_eq!(audio.payload["kind"], "audio");
  assert_eq!(audio.payload["text_source"], "saved");

  let conn = rusqlite::Connection::open(&store).expect("db");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZTYPEUTI = 'com.adobe.pdf', ZTITLE = 'notes.pdf' WHERE ZIDENTIFIER = 'att-1'",
      [],
    )
    .expect("pdf uti");
  drop(conn);
  let file = store.parent().unwrap().join("Accounts/acct-1/Media/media-1/pic.jpg");
  std::fs::write(
    &file,
    b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> >>\nendobj\n4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n",
  )
  .expect("text pdf");
  let snap = super::store::load(&store).expect("snap");
  let row = super::store::row_by_identifier(&snap.attachments, "att-1").expect("row");
  assert_eq!(super::attachment_file::attachment_kind(&store, &snap, row), "pdf");
  assert_eq!(super::attachment_file::page_count(&store, &snap, row), Some(1));

  std::fs::write(&file, pdf_with_pages(&[(8, 8), (9, 9), (10, 10)])).expect("image pdf");
  let snap = super::store::load(&store).expect("snap");
  let row = super::store::row_by_identifier(&snap.attachments, "att-1").expect("row");
  assert_eq!(super::attachment_file::attachment_kind(&store, &snap, row), "scan");
  assert_eq!(super::attachment_file::page_count(&store, &snap, row), Some(3));

  let conn = rusqlite::Connection::open(&store).expect("db");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZTYPEUTI = 'public.url' WHERE ZIDENTIFIER = 'att-drawing'",
      [],
    )
    .expect("link uti");
  drop(conn);
  let link = get_attachment(&store, "att-drawing").expect("link");
  assert_eq!(link.payload["kind"], "link");
}

#[test]
fn markdown_page_rejects_a_pdf_page_past_the_end() {
  let (_dir, store) = attachment_store();
  let pdf = store
    .parent()
    .unwrap()
    .join("Accounts/acct-1/FallbackPDFs/att-scan/226_GEN/FallbackPDF.pdf");
  std::fs::write(&pdf, pdf_with_pages(&[(10, 10), (12, 12)])).expect("pdf");
  let past = call_output(
    &store,
    "get_attachment",
    &json!({ "attachment_identifier": "att-scan", "page": 3 }),
  )
  .expect_err("page 3");
  assert_eq!(past.code, "page_out_of_range");
  assert!(past.message.contains("2 page"), "{}", past.message);
}

use serde_json::{Value, json};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, SystemTime};

use super::attachment_fixture::attachment_store;
use super::{NotesOutput, call_output, call_with_store};

fn original_lock() -> std::sync::MutexGuard<'static, ()> {
  static LOCK: Mutex<()> = Mutex::new(());
  LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
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
  assert!(gallery.file.is_none());
  assert_eq!(gallery.payload["content"], "- [Page 1.jpeg](attachment:att-page)");
  let table = get_attachment(&store, "att-table").expect("table");
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
  let page = attachments
    .iter()
    .find(|a| a["identifier"] == "att-page")
    .expect("page");
  assert_eq!(page["parent_identifier"], "att-gallery");
  assert_eq!(page["type_uti"], "public.jpeg");
  assert_eq!(page["file_name"], "Page 1.jpeg");
  assert!(page.get("parent_attachment").is_none());
  assert!(page.get("media").is_none());
  let gallery = attachments
    .iter()
    .find(|a| a["identifier"] == "att-gallery")
    .expect("gallery");
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
  assert_eq!(output.payload["image_classification_summary"], "a cat");
  assert_eq!(output.payload["ocr_summary"], "Alpha line\nBeta");
  assert!(output.payload.get("ocr_truncated").is_none());
  assert!(output.payload.get("summary").is_none());
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
      "handwriting_summary",
      "image_classification_summary",
      "additional_indexable_text",
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
  assert!(page.payload.get("ocr_summary").is_none());
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

/// `sips` renders page 1 of a generated PDF, and a non-model image is marked as a JPEG rendition.
#[cfg(target_os = "macos")]
#[test]
fn renders_a_pdf_first_page_and_marks_a_scaled_photo() {
  let (_dir, store) = attachment_store();
  let root = store.parent().unwrap();
  let pdf = root.join("Accounts/acct-1/FallbackPDFs/att-scan/226_GEN/FallbackPDF.pdf");
  std::fs::write(&pdf, one_page_pdf()).expect("pdf");
  let scan = get_attachment_as(&store, "att-scan", "image").expect("scan");
  assert_eq!(scan.payload["format"], "image");
  assert_eq!(scan.payload["rendition"], "jpeg_first_page");
  assert_eq!(scan.payload["type_uti"], "com.apple.paper.doc.scan");
  let file = scan.file.expect("jpeg");
  assert_eq!(file.mime_type, "image/jpeg");
  assert!(file.bytes.starts_with(&[0xff, 0xd8, 0xff]));

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

#[cfg(target_os = "macos")]
fn one_page_pdf() -> Vec<u8> {
  let stream = b"1 0 0 rg 40 40 120 120 re f\n";
  let contents = format!("<< /Length {} >>\nstream\n", stream.len());
  let objects: [Vec<u8>; 4] = [
    b"<< /Type /Catalog /Pages 2 0 R >>".to_vec(),
    b"<< /Type /Pages /Count 1 /Kids [3 0 R] >>".to_vec(),
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>".to_vec(),
    {
      let mut object = contents.into_bytes();
      object.extend_from_slice(stream);
      object.extend_from_slice(b"endstream");
      object
    },
  ];
  let mut out = Vec::from(&b"%PDF-1.4\n"[..]);
  let mut offsets = vec![0];
  for (index, object) in objects.iter().enumerate() {
    offsets.push(out.len());
    out.extend(format!("{} 0 obj\n", index + 1).bytes());
    out.extend_from_slice(object);
    out.extend_from_slice(b"\nendobj\n");
  }
  let xref = out.len();
  out.extend(format!("xref\n0 {}\n", objects.len() + 1).bytes());
  out.extend_from_slice(b"0000000000 65535 f \n");
  for offset in offsets.into_iter().skip(1) {
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

//! A sample store in its own folder, with gallery pages, inline attachments, and attachment files
//! laid out the way Notes keeps them under `Accounts/<account identifier>/`.

use rusqlite::{Connection, params};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use super::fixture::sample_store;

pub(super) struct TmpDir(PathBuf);

impl Drop for TmpDir {
  fn drop(&mut self) {
    let _ = std::fs::remove_dir_all(&self.0);
  }
}

pub(super) fn attachment_store() -> (TmpDir, PathBuf) {
  static NEXT: AtomicU64 = AtomicU64::new(0);
  let dir = std::env::temp_dir().join(format!(
    "abridge-notes-files-{}-{}",
    std::process::id(),
    NEXT.fetch_add(1, Ordering::Relaxed)
  ));
  std::fs::create_dir_all(&dir).expect("fixture dir");
  let guard = TmpDir(dir.clone());
  let store = dir.join("NoteStore.sqlite");
  let (_db, source) = sample_store();
  std::fs::copy(&source, &store).expect("copy store");

  let conn = Connection::open(&store).expect("fixture db");
  conn
    .execute_batch(
      "
      ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZPARENTATTACHMENT INTEGER;
      ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZGENERATION1 TEXT;
      ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZFALLBACKPDFGENERATION TEXT;
      ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZISPASSWORDPROTECTED INTEGER;
      ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZTYPEUTI1 TEXT;
      ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZALTTEXT TEXT;
      ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZTOKENCONTENTIDENTIFIER TEXT;
      INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES (6, 'ICInlineAttachment');

      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZFILENAME, ZGENERATION1)
        VALUES (31, 5, 'media-2', 'Page 1.jpeg', '1_GEN'), (32, 5, 'media-3', 'gone.jpg', NULL);
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZNOTE, ZTYPEUTI, ZMEDIA, ZPARENTATTACHMENT,
          ZFALLBACKPDFGENERATION, ZISPASSWORDPROTECTED)
        VALUES
          (43, 4, 'att-gallery', 18, 'com.apple.notes.gallery', NULL, NULL, NULL, 0),
          (42, 4, 'att-page', 18, 'public.jpeg', 31, 43, NULL, 0),
          (44, 4, 'att-scan', 18, 'com.apple.paper.doc.scan', NULL, NULL, '226_GEN', 0),
          (45, 4, 'att-drawing', 18, 'com.apple.drawing.2', NULL, NULL, NULL, 0),
          (46, 4, 'att-missing', 18, 'public.jpeg', 32, NULL, NULL, 0),
          (47, 4, 'att-locked', 18, 'public.jpeg', 30, NULL, NULL, 1);
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZNOTE, ZTYPEUTI1, ZALTTEXT, ZPARENTATTACHMENT)
        VALUES
          (60, 6, 'inline-tag', 18, 'com.apple.notes.inlinetextattachment.hashtag', '#groceries', NULL),
          (61, 6, 'inline-math', 19, 'com.apple.notes.inlinetextattachment.calculateresult', '42', 41);
      ",
    )
    .expect("attachment rows");
  let body =
    super::fixture::attachment_body_blob(&[("att-1", "public.image"), ("att-gallery", "com.apple.notes.gallery")]);
  conn
    .execute("UPDATE ZICNOTEDATA SET ZDATA = ?1 WHERE Z_PK = 1018", params![body])
    .expect("note body");

  let account = dir.join("Accounts/acct-1");
  write(&account.join("Media/media-1/pic.jpg"), b"jpeg bytes");
  write(&account.join("Media/media-2/1_GEN/Page 1.jpeg"), b"page bytes");
  write(
    &account.join("FallbackPDFs/att-scan/226_GEN/FallbackPDF.pdf"),
    b"%PDF scan",
  );
  write(&account.join("FallbackImages/att-drawing.png"), b"png bytes");
  (guard, store)
}

fn write(path: &Path, bytes: &[u8]) {
  std::fs::create_dir_all(path.parent().expect("parent")).expect("file dir");
  std::fs::write(path, bytes).expect("fixture file");
}

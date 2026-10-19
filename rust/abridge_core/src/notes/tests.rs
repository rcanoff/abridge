use serde_json::Value;
use std::path::Path;

use super::attributes::{self, ACCOUNT, FOLDER, MEDIA};
use super::call_with_store;
use super::fixture::{add_recently_deleted, sample_store};
use super::note_attributes::{ATTACHMENT, NOTE};
use super::store::{self, SqlValue};
use super::store_path_for_home;

fn fetch_note(store: &Path, identifier: &str) -> Value {
  call_with_store(store, "get_note", &serde_json::json!({ "note_identifier": identifier })).expect("note")
}

#[test]
fn attribute_tables_cover_the_model_scalars() {
  assert_eq!(ACCOUNT.len(), 33);
  assert_eq!(FOLDER.len(), 28);
  assert_eq!(NOTE.len(), 47);
  assert_eq!(ATTACHMENT.len(), 62);
  assert_eq!(MEDIA.len(), 18);
  assert_eq!(attributes::attributes_for("ICInlineAttachment").len(), 22);
  assert!(ACCOUNT.iter().any(|attr| attr.name == "identifier"));
  assert!(NOTE.iter().any(|attr| attr.name == "creationDate"));
  assert!(ATTACHMENT.iter().any(|attr| attr.name == "typeUTI"));
  assert_eq!(attributes::attributes_for("ICNote").len(), 47);
}

#[test]
fn default_store_path_uses_home() {
  let path = store_path_for_home("/tmp/notes-home");
  assert_eq!(
    path,
    Path::new("/tmp/notes-home/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
  );
}

#[test]
fn resolves_suffixed_columns_and_projects_bool_date_and_null() {
  let (_db, path) = sample_store();
  let note = fetch_note(&path, "note-a");
  assert_eq!(note["title"], "From suffix");
  assert_eq!(note["is_pinned"], true);
  assert_eq!(note["creation_date"], "2001-01-01T00:00:00Z");
  assert_eq!(note["body"], "gzip text");
  assert!(note.get("snippet").is_none());
  assert!(note.get("password_hint").is_none());
  assert!(note.get("note_data").is_none());
  assert!(note.get("account").is_none());
  assert!(note.get("attachments").is_none());
  assert_eq!(note["folder"]["identifier"], "fold-1");
  assert_eq!(note["folder"]["path"], "Notes");
  assert_eq!(note["folder"]["account"], "Personal");

  let unpinned = fetch_note(&path, "note-b");
  assert!(unpinned.get("is_pinned").is_none());
  assert!(unpinned.get("title").is_none());
  assert!(unpinned.get("creation_date").is_none());
  assert_eq!(unpinned["body"], "zlib text");

  let ambiguous = fetch_note(&path, "note-k");
  assert!(ambiguous.get("title").is_none());

  let carrier = fetch_note(&path, "note-i");
  let attachment = &carrier["attachments"][0];
  assert_eq!(attachment["identifier"], "att-1");
  assert_eq!(attachment["title"], "Beta Unique");
  assert_eq!(attachment["file_name"], "pic.jpg");
  assert_eq!(attachment["type_uti"], "public.image");
  assert_eq!(attachment["ocr_summary"], "ocr hit");
  assert_eq!(attachment["handwriting_summary"], "ink hit");
  assert!(attachment.get("summary").is_none());
  assert_eq!(attachment["url"], "https://example.com/hidden");
  assert!(attachment.get("media").is_none());
  assert!(attachment.get("mergeable_data").is_none());
  assert!(carrier.get("inline_attachments").is_none());
  assert_eq!(carrier["body"], "[Beta Unique](attachment:att-1)");

  let folders = call_with_store(
    &path,
    "list_folders",
    &serde_json::json!({ "account_identifier": "acct-1" }),
  )
  .unwrap();
  let listed = folders.as_array().unwrap();
  assert_eq!(listed.len(), 2);
  assert_eq!(listed[0]["name"], "Notes");
  assert_eq!(listed[0]["path"], "Notes");
  assert_eq!(listed[1]["name"], "Archive");
  assert_eq!(listed[1]["path"], "Notes/Archive");
  assert_eq!(listed[1]["parent_identifier"], "fold-1");
  let missing = call_with_store(
    &path,
    "list_folders",
    &serde_json::json!({ "account_identifier": "missing" }),
  )
  .unwrap();
  assert_eq!(missing.as_array().unwrap().len(), 0);
}

#[test]
fn decodes_gzip_zlib_encrypted_null_and_malformed_bodies() {
  let (_db, path) = sample_store();
  assert_eq!(fetch_note(&path, "note-a")["body"], "gzip text");
  assert_eq!(fetch_note(&path, "note-b")["body"], "zlib text");
  assert!(fetch_note(&path, "note-c").get("body").is_none());
  assert!(fetch_note(&path, "note-d").get("body").is_none());
  assert!(fetch_note(&path, "note-e").get("body").is_none());
  assert!(fetch_note(&path, "note-g").get("body").is_none());
  assert!(call_with_store(&path, "list_notes", &serde_json::json!({})).is_ok());
}

#[test]
fn decodes_attribute_runs_paragraphs_and_todos() {
  let (_db, path) = sample_store();
  let snap = store::load(&path).expect("store");
  let note = store::row_by_identifier(&snap.notes, "note-f").expect("note");
  let pk = store::foreign_key(note, "noteData").expect("note data");
  let row = snap.note_data.iter().find(|row| row.pk == pk).expect("row");
  let data = super::decode::decode_note_blob(row.data.as_deref().expect("blob")).expect("decoded");
  let data = &data;
  assert_eq!(data["string"], "Hello\u{FFFC}");
  let run = &data["attribute_runs"][0];
  assert_eq!(
    run,
    &serde_json::json!({
      "length": 6,
      "paragraph_style": {
        "style": 1,
        "alignment": 2,
        "writing_direction": 1,
        "indent": 3,
        "todo": { "uuid": "00112233-4455-6677-8899-AABBCCDDEEFF", "done": true },
        "block_quote_level": 0,
        "uuid": "00112233-4455-6677-8899-AABBCCDDEEFF"
      },
      "font": { "font_name": "Helvetica", "point_size": 12.0, "font_hints": 1 },
      "font_weight": 6,
      "underlined": 1,
      "strikethrough": 0,
      "superscript": -1,
      "link": "https://example.com",
      "color": { "red": 1.0, "green": 0.0, "blue": 0.5, "alpha": 1.0 },
      "attachment_info": { "attachment_identifier": "ATT-1", "type_uti": "public.png" },
      "timestamp": "1970-01-01T00:00:00Z",
      "emphasis": 2
    })
  );
}

#[test]
fn reconstructs_a_right_to_left_table_from_the_suffixed_blob() {
  let (_db, path) = sample_store();
  let snap = store::load(&path).expect("store");
  let stored = snap
    .attachments
    .iter()
    .find(|row| store::text(row, "identifier") == Some("att-table"))
    .expect("table");
  let SqlValue::Blob(blob) = store::non_null(stored, "mergeableData").expect("blob") else {
    panic!("mergeable data");
  };
  let decoded = super::table::decode_mergeable(blob).expect("table");
  let table = &decoded["table"];
  assert_eq!(table["column_direction"], "CRTableColumnDirectionRightToLeft");
  assert_eq!(table["rows"][0][0]["string"], "Right");
  assert_eq!(table["rows"][0][1]["string"], "Left");
  assert_eq!(table["rows"][0][0]["attribute_runs"], serde_json::json!([]));

  let note = fetch_note(&path, "note-j");
  assert!(note.get("attachments").is_none());
  assert!(note.get("attachment_count").is_none());
  assert!(note["body"].as_str().unwrap().contains("| Right | Left |"));
}

#[test]
fn lists_notes_in_a_folder_then_pages() {
  let (_db, path) = sample_store();
  let listed = call_with_store(
    &path,
    "list_notes",
    &serde_json::json!({ "folder_identifier": "fold-1", "limit": 1, "offset": 0 }),
  )
  .unwrap();
  assert_eq!(listed[0]["identifier"], "note-a");
  let all = call_with_store(&path, "list_notes", &serde_json::json!({})).unwrap();
  assert!(all.as_array().unwrap().len() > 1);
  assert!(all.as_array().unwrap().len() <= 50);
}

#[test]
fn missing_and_unopenable_stores_use_distinct_errors() {
  let missing = call_with_store(
    Path::new("/tmp/abridge-notes-missing-store.sqlite"),
    "list_folders",
    &serde_json::json!({}),
  )
  .unwrap_err();
  assert_eq!(missing.code, "notes_store_not_found");

  let dir = std::env::temp_dir().join(format!("abridge-notes-dir-{}", std::process::id()));
  std::fs::create_dir_all(&dir).unwrap();
  let err = call_with_store(&dir, "list_folders", &serde_json::json!({})).unwrap_err();
  let _ = std::fs::remove_dir_all(&dir);
  assert_eq!(err.code, "full_disk_access_required");

  let absent = call_with_store(
    Path::new("/tmp/abridge-notes-missing-store.sqlite"),
    "get_note",
    &serde_json::json!({ "note_identifier": "note-a" }),
  )
  .unwrap_err();
  assert_eq!(absent.code, "notes_store_not_found");
}

#[test]
fn missing_note_is_not_found_and_writes_do_not_spawn_for_a_missing_store() {
  let (_db, path) = sample_store();
  let missing = call_with_store(&path, "get_note", &serde_json::json!({ "note_identifier": "nope" })).unwrap_err();
  assert_eq!(missing.code, "not_found");

  let create = call_with_store(
    Path::new("/tmp/abridge-notes-missing-store.sqlite"),
    "create_note",
    &serde_json::json!({ "folder_identifier": "fold-1", "body": "<h1>Hi</h1>" }),
  )
  .unwrap_err();
  assert_eq!(create.code, "notes_store_not_found");

  let update = call_with_store(
    Path::new("/tmp/abridge-notes-missing-store.sqlite"),
    "update_note",
    &serde_json::json!({ "note_identifier": "note-a" }),
  )
  .unwrap_err();
  assert_eq!(update.code, "notes_error");

  let folder = call_with_store(
    Path::new("/tmp/abridge-notes-missing-store.sqlite"),
    "create_folder",
    &serde_json::json!({ "name": "New", "account_identifier": "a", "folder_identifier": "b" }),
  )
  .unwrap_err();
  assert_eq!(folder.code, "notes_error");
}

#[test]
fn create_folder_reports_the_sibling_that_holds_the_name() {
  let (_db, store) = sample_store();

  let top_level = call_with_store(
    &store,
    "create_folder",
    &serde_json::json!({ "name": "Notes", "account_identifier": "acct-1" }),
  )
  .unwrap_err();
  assert_eq!(top_level.code, "folder_name_taken");
  assert!(top_level.message.contains("fold-1"));

  let nested = call_with_store(
    &store,
    "create_folder",
    &serde_json::json!({ "name": "Archive", "folder_identifier": "fold-1" }),
  )
  .unwrap_err();
  assert_eq!(nested.code, "folder_name_taken");
  assert!(nested.message.contains("fold-2"));
}

#[test]
fn delete_note_refuses_notes_already_in_recently_deleted() {
  let (_db, store) = sample_store();
  add_recently_deleted(&store);

  let error = call_with_store(
    &store,
    "delete_note",
    &serde_json::json!({ "note_identifier": "note-trashed" }),
  )
  .unwrap_err();
  assert_eq!(error.code, "note_in_recently_deleted");
}

#[test]
fn note_detail_lists_only_attachments_the_body_references() {
  let (_db, path) = sample_store();
  let conn = rusqlite::Connection::open(&path).expect("fixture db");
  conn
    .execute(
      "INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZNOTE, ZTYPEUTI)
       VALUES (48, 4, 'att-stale', 19, 'public.png')",
      [],
    )
    .expect("stale attachment");

  let note = fetch_note(&path, "note-j");
  assert!(note.get("attachments").is_none());
  assert!(note.get("attachment_count").is_none());
  assert!(note["body"].as_str().unwrap().contains("| Right | Left |"));

  let listed = call_with_store(
    &path,
    "list_notes",
    &serde_json::json!({ "folder_identifier": "fold-1" }),
  )
  .unwrap();
  let table = listed
    .as_array()
    .unwrap()
    .iter()
    .find(|summary| summary["identifier"] == "note-j")
    .expect("note");
  assert!(table.get("attachment_count").is_none());
}

#[test]
fn ocr_keeps_one_copy_caps_note_detail_and_stays_searchable() {
  let (_db, path) = sample_store();
  let conn = rusqlite::Connection::open(&path).expect("fixture db");
  conn
    .execute_batch("ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZADDITIONALINDEXABLETEXT TEXT")
    .expect("column");
  let line = format!("{}zzocrendtoken", "a".repeat(2100));
  let raw = format!("{line}\t{line}");
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT
       SET ZOCRSUMMARY = ?1, ZSUMMARY = ?1, ZADDITIONALINDEXABLETEXT = ?2
       WHERE ZIDENTIFIER = 'att-1'",
      rusqlite::params![raw, line],
    )
    .expect("ocr");

  let note = fetch_note(&path, "note-i");
  let attachment = &note["attachments"][0];
  let summary = attachment["ocr_summary"].as_str().unwrap();
  assert_eq!(summary.chars().count(), 2000);
  assert!(!summary.contains("zzocrendtoken"));
  assert_eq!(attachment["ocr_truncated"], true);
  assert!(attachment.get("summary").is_none());
  assert!(attachment.get("additional_indexable_text").is_none());

  let found = call_with_store(&path, "search_notes", &serde_json::json!({ "query": "'zzocrendtoken" })).unwrap();
  assert_eq!(found[0]["identifier"], "note-i");
}

#[test]
fn list_folders_omits_folders_notes_has_not_downloaded() {
  let (_db, path) = sample_store();
  let conn = rusqlite::Connection::open(&path).expect("fixture db");
  conn
    .execute_batch(
      "
      ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZNEEDSINITIALFETCHFROMCLOUD INTEGER;
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZACCOUNT8, ZNEEDSINITIALFETCHFROMCLOUD)
        VALUES (70, 2, 'fold-pending', 'Notes', 1, 1);
      ",
    )
    .expect("pending folder");
  let folders = call_with_store(&path, "list_folders", &serde_json::json!({})).unwrap();
  let identifiers: Vec<_> = folders
    .as_array()
    .unwrap()
    .iter()
    .map(|folder| folder["identifier"].as_str().unwrap())
    .collect();
  assert!(identifiers.contains(&"fold-1"));
  assert!(!identifiers.contains(&"fold-pending"));
}

fn identifiers(value: &Value) -> Vec<&str> {
  value
    .as_array()
    .unwrap()
    .iter()
    .filter_map(|item| item["identifier"].as_str())
    .collect()
}

#[test]
fn resolves_folder_path_case_insensitively() {
  let (_db, path) = sample_store();
  let archived = call_with_store(
    &path,
    "list_notes",
    &serde_json::json!({ "folder_path": "notes/archive" }),
  )
  .unwrap();
  let archived = identifiers(&archived);
  assert!(archived.contains(&"note-c"));
  assert!(archived.contains(&"note-i"));
  assert!(!archived.contains(&"note-a"));

  let notes = call_with_store(&path, "list_notes", &serde_json::json!({ "folder_path": "NOTES" })).unwrap();
  let notes = identifiers(&notes);
  assert!(notes.contains(&"note-a"));
  assert!(!notes.contains(&"note-c"));

  let found = call_with_store(
    &path,
    "search_notes",
    &serde_json::json!({ "query": "alpha unique", "folder_path": "notes" }),
  )
  .unwrap();
  assert_eq!(found[0]["identifier"], "note-h");
  let missed = call_with_store(
    &path,
    "search_notes",
    &serde_json::json!({ "query": "alpha unique", "folder_path": "Notes/Archive" }),
  )
  .unwrap();
  assert!(missed.as_array().unwrap().is_empty());
}

#[test]
fn folder_path_reports_missing_ambiguous_and_skips_undownloaded() {
  let (_db, path) = sample_store();
  let missing = call_with_store(
    &path,
    "list_notes",
    &serde_json::json!({ "folder_path": "Work/Clients" }),
  )
  .unwrap_err();
  assert_eq!(missing.code, "folder_path_not_found");
  assert_eq!(
    missing.message,
    "no folder at \"Work/Clients\". Candidates: Notes (fold-1); Notes/Archive (fold-2)."
  );

  let both = call_with_store(
    &path,
    "list_notes",
    &serde_json::json!({ "folder_identifier": "fold-1", "folder_path": "Notes" }),
  )
  .unwrap_err();
  assert_eq!(both.code, "notes_error");
  assert!(both.message.contains("exactly one of folder_identifier or folder_path"));

  let account_only = call_with_store(
    &path,
    "list_notes",
    &serde_json::json!({ "account_identifier": "acct-1" }),
  )
  .unwrap_err();
  assert!(
    account_only
      .message
      .contains("account_identifier applies only with folder_path")
  );

  let conn = rusqlite::Connection::open(&path).expect("fixture db");
  conn
    .execute_batch(
      "
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZNAME)
        VALUES (50, 1, 'acct-2', 'Work');
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZACCOUNT8)
        VALUES (51, 2, 'fold-work', 'Notes', 50);
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER, ZMODIFICATIONDATE1)
        VALUES (52, 3, 'note-work', 'Work item', 50, 51, 100);
      ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZNEEDSINITIALFETCHFROMCLOUD INTEGER;
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZACCOUNT8, ZNEEDSINITIALFETCHFROMCLOUD)
        VALUES (70, 2, 'fold-cloud', 'CloudOnly', 1, 1);
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER)
        VALUES (71, 3, 'note-cloud', 'Cloud note', 1, 70);
      ",
    )
    .expect("extra folders");
  drop(conn);

  let ambiguous = call_with_store(&path, "list_notes", &serde_json::json!({ "folder_path": "Notes" })).unwrap_err();
  assert_eq!(ambiguous.code, "folder_path_ambiguous");
  assert_eq!(
    ambiguous.message,
    "\"Notes\" matches more than one folder. Candidates: Notes (fold-1); Notes (fold-work). Pass account_identifier to choose one."
  );

  let work = call_with_store(
    &path,
    "list_notes",
    &serde_json::json!({ "folder_path": "notes", "account_identifier": "acct-2" }),
  )
  .unwrap();
  assert_eq!(identifiers(&work), vec!["note-work"]);

  let wrong_account = call_with_store(
    &path,
    "list_notes",
    &serde_json::json!({ "folder_path": "Notes/Archive", "account_identifier": "acct-2" }),
  )
  .unwrap_err();
  assert_eq!(wrong_account.code, "folder_path_not_found");
  assert!(wrong_account.message.contains("in account acct-2"));
  assert!(wrong_account.message.contains("Notes (fold-work)"));
  assert!(!wrong_account.message.contains("fold-2"));

  let unknown_account = call_with_store(
    &path,
    "list_notes",
    &serde_json::json!({ "folder_path": "Notes", "account_identifier": "missing" }),
  )
  .unwrap_err();
  assert_eq!(unknown_account.code, "not_found");
  assert_eq!(unknown_account.message, "account not found");

  let cloud = call_with_store(&path, "list_notes", &serde_json::json!({ "folder_path": "CloudOnly" })).unwrap_err();
  assert_eq!(cloud.code, "folder_path_not_found");
  assert!(!cloud.message.contains("fold-cloud"));
  let by_id = call_with_store(
    &path,
    "list_notes",
    &serde_json::json!({ "folder_identifier": "fold-cloud" }),
  )
  .unwrap();
  assert_eq!(identifiers(&by_id), vec!["note-cloud"]);
}

#[test]
fn resolves_note_title_and_skips_recently_deleted() {
  let (_db, path) = sample_store();
  let note = call_with_store(&path, "get_note", &serde_json::json!({ "note_title": "FROM SUFFIX" })).unwrap();
  assert_eq!(note["identifier"], "note-a");

  let narrowed = call_with_store(
    &path,
    "get_note",
    &serde_json::json!({ "note_title": "from suffix", "folder_path": "notes" }),
  )
  .unwrap();
  assert_eq!(narrowed["identifier"], "note-a");
  let other_folder = call_with_store(
    &path,
    "get_note",
    &serde_json::json!({ "note_title": "from suffix", "folder_path": "notes/archive" }),
  )
  .unwrap_err();
  assert_eq!(other_folder.code, "not_found");
  assert!(other_folder.message.contains("no note titled"));

  let missing = call_with_store(&path, "get_note", &serde_json::json!({ "note_title": "missing" })).unwrap_err();
  assert_eq!(missing.code, "not_found");

  let neither = call_with_store(&path, "get_note", &serde_json::json!({})).unwrap_err();
  assert_eq!(neither.code, "notes_error");
  assert!(neither.message.contains("exactly one of note_identifier or note_title"));
  let both = call_with_store(
    &path,
    "get_note",
    &serde_json::json!({ "note_identifier": "note-a", "note_title": "From suffix" }),
  )
  .unwrap_err();
  assert!(both.message.contains("exactly one of note_identifier or note_title"));

  let conn = rusqlite::Connection::open(&path).expect("fixture db");
  conn
    .execute_batch(
      "
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER, ZMODIFICATIONDATE1)
        VALUES (60, 3, 'note-twin-a', 'Twin', 1, 2, 10);
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER, ZMODIFICATIONDATE1)
        VALUES (61, 3, 'note-twin-b', 'Twin', 1, 3, 20);
      ",
    )
    .expect("twins");
  drop(conn);

  let ambiguous = call_with_store(&path, "get_note", &serde_json::json!({ "note_title": "twin" })).unwrap_err();
  assert_eq!(ambiguous.code, "note_title_ambiguous");
  assert!(
    ambiguous
      .message
      .contains("note-twin-b in Notes/Archive, modified 2001-01-01T00:00:20Z")
  );
  assert!(
    ambiguous
      .message
      .contains("note-twin-a in Notes, modified 2001-01-01T00:00:10Z")
  );
  let archive = call_with_store(
    &path,
    "get_note",
    &serde_json::json!({ "note_title": "Twin", "folder_identifier": "fold-2" }),
  )
  .unwrap();
  assert_eq!(archive["identifier"], "note-twin-b");

  add_recently_deleted(&path);
  let hidden = call_with_store(&path, "get_note", &serde_json::json!({ "note_title": "Old" })).unwrap_err();
  assert_eq!(hidden.code, "not_found");
  let trashed = call_with_store(
    &path,
    "get_note",
    &serde_json::json!({ "note_title": "old", "folder_path": "recently deleted" }),
  )
  .unwrap();
  assert_eq!(trashed["identifier"], "note-trashed");

  let delete_hidden = call_with_store(&path, "delete_note", &serde_json::json!({ "note_title": "Old" })).unwrap_err();
  assert_eq!(delete_hidden.code, "not_found");
  let delete_trash = call_with_store(
    &path,
    "delete_note",
    &serde_json::json!({ "note_title": "Old", "folder_path": "Recently Deleted" }),
  )
  .unwrap_err();
  assert_eq!(delete_trash.code, "note_in_recently_deleted");

  let conn = rusqlite::Connection::open(&path).expect("fixture db");
  conn
    .execute(
      "INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER, ZMODIFICATIONDATE1)
       VALUES (62, 3, 'note-live-old', 'Old', 1, 2, 30)",
      [],
    )
    .expect("live old");
  drop(conn);
  let live = call_with_store(&path, "get_note", &serde_json::json!({ "note_title": "Old" })).unwrap();
  assert_eq!(live["identifier"], "note-live-old");
}

#[test]
fn note_title_lists_at_most_ten_live_candidates() {
  let (_db, path) = sample_store();
  let conn = rusqlite::Connection::open(&path).expect("fixture db");
  let mut sql = String::from(
    "
    ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZMARKEDFORDELETION INTEGER;
    ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZNEEDSINITIALFETCHFROMCLOUD INTEGER;
    ",
  );
  for index in 1..=11 {
    sql.push_str(&format!(
      "INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER, ZMODIFICATIONDATE1)
       VALUES ({pk}, 3, 'note-dup-{index:02}', 'Dup', 1, 2, {index}.0);\n",
      pk = 200 + index
    ));
  }
  sql.push_str(
    "
    INSERT INTO ZICCLOUDSYNCINGOBJECT
      (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER, ZMODIFICATIONDATE1, ZMARKEDFORDELETION)
      VALUES (220, 3, 'note-deleted', 'Dup', 1, 2, 50, 1);
    INSERT INTO ZICCLOUDSYNCINGOBJECT
      (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER, ZMODIFICATIONDATE1, ZNEEDSINITIALFETCHFROMCLOUD)
      VALUES (221, 3, 'note-cloud', 'Dup', 1, 2, 49, 1);
    ",
  );
  conn.execute_batch(&sql).expect("duplicates");
  drop(conn);
  add_recently_deleted(&path);
  let conn = rusqlite::Connection::open(&path).expect("fixture db");
  conn
    .execute(
      "INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER, ZMODIFICATIONDATE1)
       VALUES (230, 3, 'note-trash-dup', 'Dup', 1, 90, 80)",
      [],
    )
    .expect("trash duplicate");
  drop(conn);

  let ambiguous = call_with_store(&path, "get_note", &serde_json::json!({ "note_title": "dup" })).unwrap_err();
  assert_eq!(ambiguous.code, "note_title_ambiguous");
  assert!(
    ambiguous
      .message
      .contains("note-dup-11 in Notes, modified 2001-01-01T00:00:11Z")
  );
  assert!(ambiguous.message.contains("note-dup-02"));
  assert!(ambiguous.message.contains("and 1 more"));
  assert!(!ambiguous.message.contains("note-dup-01"));
  assert!(!ambiguous.message.contains("note-deleted"));
  assert!(!ambiguous.message.contains("note-cloud"));
  assert!(!ambiguous.message.contains("note-trash-dup"));
}

#[test]
fn writes_resolve_path_and_title_before_scripting() {
  let (_db, path) = sample_store();
  let taken = call_with_store(
    &path,
    "create_folder",
    &serde_json::json!({ "name": "Archive", "folder_path": "Notes" }),
  )
  .unwrap_err();
  assert_eq!(taken.code, "folder_name_taken");
  assert!(taken.message.contains("fold-2"));

  let taken_in_account = call_with_store(
    &path,
    "create_folder",
    &serde_json::json!({ "name": "Archive", "folder_path": "notes", "account_identifier": "acct-1" }),
  )
  .unwrap_err();
  assert_eq!(taken_in_account.code, "folder_name_taken");

  let not_empty = call_with_store(&path, "delete_folder", &serde_json::json!({ "folder_path": "notes" })).unwrap_err();
  assert_eq!(not_empty.code, "folder_not_empty");

  let create = call_with_store(
    &path,
    "create_note",
    &serde_json::json!({ "body": "Hello", "folder_path": "missing" }),
  )
  .unwrap_err();
  assert_eq!(create.code, "folder_path_not_found");
  let create_neither = call_with_store(&path, "create_note", &serde_json::json!({ "body": "Hello" })).unwrap_err();
  assert!(
    create_neither
      .message
      .contains("exactly one of folder_identifier or folder_path")
  );
  let create_both = call_with_store(
    &path,
    "create_note",
    &serde_json::json!({ "body": "Hello", "folder_identifier": "fold-1", "folder_path": "Notes" }),
  )
  .unwrap_err();
  assert!(
    create_both
      .message
      .contains("exactly one of folder_identifier or folder_path")
  );

  let update = call_with_store(
    &path,
    "update_note",
    &serde_json::json!({ "note_title": "carrier", "body": "x" }),
  )
  .unwrap_err();
  assert_eq!(update.code, "body_would_drop_content");

  let moved = call_with_store(
    &path,
    "move_note",
    &serde_json::json!({ "note_title": "from suffix", "folder_path": "no/such" }),
  )
  .unwrap_err();
  assert_eq!(moved.code, "folder_path_not_found");
  let move_neither =
    call_with_store(&path, "move_note", &serde_json::json!({ "note_title": "from suffix" })).unwrap_err();
  assert!(
    move_neither
      .message
      .contains("exactly one of folder_identifier or folder_path")
  );
}

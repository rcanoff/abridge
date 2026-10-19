//! In-memory Notes store fixtures. Never opens the real store or osascript.

use flate2::Compression;
use flate2::write::{GzEncoder, ZlibEncoder};
use prost::Message;
use rusqlite::{Connection, params};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use super::proto_note::{
  AttachmentInfo, AttributeRun, Color, Font, NoteDocument, NoteVersion, ParagraphStyle, Todo, TopotextString,
};
use super::proto_table::{
  Dictionary, DictionaryElement, MapEntry, MergableDataObject, MergableDataProto, MergeableDataObjectData,
  MergeableDataObjectEntry, MergeableDataObjectMap, ObjectId, OrderedSet, OrderedSetOrdering, OrderedSetOrderingArray,
  OrderedSetOrderingArrayAttachment,
};

const ACCOUNT: i64 = 1;
const FOLDER: i64 = 2;
const NOTE: i64 = 3;
const ATTACHMENT: i64 = 4;
const MEDIA: i64 = 5;

pub(crate) struct TmpDb(PathBuf);

impl Drop for TmpDb {
  fn drop(&mut self) {
    let _ = std::fs::remove_file(&self.0);
  }
}

impl TmpDb {
  fn path(&self) -> &Path {
    &self.0
  }
}

pub(crate) fn sample_store() -> (TmpDb, PathBuf) {
  let db = temp_db();
  let conn = Connection::open(db.path()).expect("fixture db");
  conn
    .execute_batch(
      "
      CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME TEXT, Z_SUPER INTEGER, Z_MAX INTEGER);
      CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID TEXT, Z_PLIST BLOB);
      CREATE TABLE ZICCLOUDSYNCINGOBJECT (
        Z_PK INTEGER PRIMARY KEY,
        Z_ENT INTEGER,
        Z_OPT INTEGER,
        ZIDENTIFIER TEXT,
        ZNAME TEXT,
        ZTITLE TEXT,
        ZTITLE1 TEXT,
        ZTITLE2 TEXT,
        ZSNIPPET TEXT,
        ZISPINNED INTEGER,
        ZCREATIONDATE REAL,
        ZCREATIONDATE1 REAL,
        ZMODIFICATIONDATE REAL,
        ZMODIFICATIONDATE1 REAL,
        ZACCOUNT INTEGER,
        ZACCOUNT8 INTEGER,
        ZFOLDER INTEGER,
        ZPARENT INTEGER,
        ZNOTE INTEGER,
        ZMEDIA INTEGER,
        ZNOTEDATA INTEGER,
        ZTYPEUTI TEXT,
        ZSUMMARY TEXT,
        ZOCRSUMMARY TEXT,
        ZHANDWRITINGSUMMARY TEXT,
        ZURLSTRING TEXT,
        ZMERGEABLEDATA BLOB,
        ZMERGEABLEDATA1 BLOB,
        ZFILENAME TEXT
      );
      CREATE TABLE ZICNOTEDATA (
        Z_PK INTEGER PRIMARY KEY,
        Z_ENT INTEGER,
        Z_OPT INTEGER,
        ZNOTE INTEGER,
        ZDATA BLOB,
        ZCRYPTOTAG BLOB
      );
      INSERT INTO Z_PRIMARYKEY (Z_ENT, Z_NAME) VALUES
        (1, 'ICAccount'), (2, 'ICFolder'), (3, 'ICNote'), (4, 'ICAttachment'), (5, 'ICMedia');
      INSERT INTO Z_METADATA (Z_VERSION, Z_UUID) VALUES (1, 'TEST-UUID');
      ",
    )
    .expect("schema");

  insert(
    &conn,
    Obj {
      pk: 1,
      ent: ACCOUNT,
      identifier: Some("acct-1".into()),
      name: Some("Personal".into()),
      ..Obj::default()
    },
  );
  insert(
    &conn,
    Obj {
      pk: 2,
      ent: FOLDER,
      identifier: Some("fold-1".into()),
      title2: Some("Notes".into()),
      account8: Some(1),
      ..Obj::default()
    },
  );
  insert(
    &conn,
    Obj {
      pk: 3,
      ent: FOLDER,
      identifier: Some("fold-2".into()),
      title2: Some("Archive".into()),
      account8: Some(1),
      parent: Some(2),
      ..Obj::default()
    },
  );
  insert_note(
    &conn,
    10,
    "note-a",
    2,
    Some("From suffix"),
    Some("alpha snippet"),
    Some(1),
    Some(0.0),
    Some(1010),
  );
  insert_note(
    &conn,
    11,
    "note-b",
    2,
    None,
    Some("shared token"),
    Some(0),
    None,
    Some(1011),
  );
  insert_note(
    &conn,
    12,
    "note-c",
    3,
    Some("Encrypted"),
    Some("encrypted"),
    None,
    None,
    Some(1012),
  );
  insert_note(
    &conn,
    13,
    "note-d",
    3,
    Some("Null data"),
    Some("shared token"),
    None,
    None,
    Some(1013),
  );
  insert_note(&conn, 14, "note-e", 2, Some("Malformed"), None, None, None, Some(1014));
  insert_note(&conn, 15, "note-f", 2, Some("Rich"), None, None, None, Some(1015));
  insert_note(
    &conn,
    16,
    "note-g",
    2,
    Some("Missing data"),
    Some("shared token"),
    None,
    None,
    None,
  );
  insert_note(&conn, 17, "note-h", 2, Some("other"), None, None, None, Some(1017));
  insert_note(&conn, 18, "note-i", 3, Some("Carrier"), None, None, None, Some(1018));
  insert_note(&conn, 19, "note-j", 2, Some("Table"), None, None, None, Some(1019));
  insert_note(&conn, 20, "note-k", 2, None, None, None, None, None);
  conn
    .execute(
      "UPDATE ZICCLOUDSYNCINGOBJECT SET ZTITLE = 'one', ZTITLE1 = 'two' WHERE Z_PK = 20",
      [],
    )
    .unwrap();

  insert_data(&conn, 1010, Some(gzip(&plain_note("gzip text"))), None);
  let zlib_blob = zlib(&plain_note("zlib text"));
  assert!(
    zlib_blob.starts_with(&[0x78, 0x9c]),
    "fixture zlib header {:02x?}",
    &zlib_blob[..2]
  );
  insert_data(&conn, 1011, Some(zlib_blob), None);
  insert_data(&conn, 1012, Some(gzip(&plain_note("secret"))), Some(b"tag".to_vec()));
  insert_data(&conn, 1013, None, None);
  insert_data(&conn, 1014, Some(b"not-a-protobuf".to_vec()), None);
  insert_data(&conn, 1015, Some(gzip(&rich_note())), None);
  insert_data(&conn, 1017, Some(gzip(&plain_note("Alpha Unique"))), None);
  insert_data(
    &conn,
    1018,
    Some(attachment_body_blob(&[("att-1", "public.image")])),
    None,
  );
  insert_data(
    &conn,
    1019,
    Some(attachment_body_blob(&[("att-table", "com.apple.notes.table")])),
    None,
  );

  insert(
    &conn,
    Obj {
      pk: 30,
      ent: MEDIA,
      identifier: Some("media-1".into()),
      filename: Some("pic.jpg".into()),
      ..Obj::default()
    },
  );
  insert(
    &conn,
    Obj {
      pk: 40,
      ent: ATTACHMENT,
      identifier: Some("att-1".into()),
      title: Some("Beta Unique".into()),
      note: Some(18),
      media: Some(30),
      type_uti: Some("public.image".into()),
      summary: Some("sum".into()),
      ocr: Some("ocr hit".into()),
      handwriting: Some("ink hit".into()),
      url: Some("https://example.com/hidden".into()),
      ..Obj::default()
    },
  );
  insert(
    &conn,
    Obj {
      pk: 41,
      ent: ATTACHMENT,
      identifier: Some("att-table".into()),
      note: Some(19),
      type_uti: Some("com.apple.notes.table".into()),
      mergeable1: Some(rtl_table_blob()),
      ..Obj::default()
    },
  );
  drop(conn);
  let path = db.path().to_path_buf();
  (db, path)
}

#[allow(clippy::too_many_arguments)]
fn insert_note(
  conn: &Connection,
  pk: i64,
  identifier: &str,
  folder: i64,
  title1: Option<&str>,
  snippet: Option<&str>,
  pinned: Option<i64>,
  creation1: Option<f64>,
  note_data: Option<i64>,
) {
  insert(
    conn,
    Obj {
      pk,
      ent: NOTE,
      identifier: Some(identifier.into()),
      title1: title1.map(str::to_string),
      snippet: snippet.map(str::to_string),
      pinned,
      creation1,
      modification1: Some(100.0),
      account: Some(1),
      folder: Some(folder),
      note_data,
      ..Obj::default()
    },
  );
}

#[derive(Default)]
struct Obj {
  pk: i64,
  ent: i64,
  identifier: Option<String>,
  name: Option<String>,
  title: Option<String>,
  title1: Option<String>,
  title2: Option<String>,
  snippet: Option<String>,
  pinned: Option<i64>,
  creation: Option<f64>,
  creation1: Option<f64>,
  modification: Option<f64>,
  modification1: Option<f64>,
  account: Option<i64>,
  account8: Option<i64>,
  folder: Option<i64>,
  parent: Option<i64>,
  note: Option<i64>,
  media: Option<i64>,
  note_data: Option<i64>,
  type_uti: Option<String>,
  summary: Option<String>,
  ocr: Option<String>,
  handwriting: Option<String>,
  url: Option<String>,
  mergeable: Option<Vec<u8>>,
  mergeable1: Option<Vec<u8>>,
  filename: Option<String>,
}

fn insert(conn: &Connection, row: Obj) {
  conn
    .execute(
      "INSERT INTO ZICCLOUDSYNCINGOBJECT (
        Z_PK, Z_ENT, Z_OPT, ZIDENTIFIER, ZNAME, ZTITLE, ZTITLE1, ZTITLE2, ZSNIPPET, ZISPINNED,
        ZCREATIONDATE, ZCREATIONDATE1, ZMODIFICATIONDATE, ZMODIFICATIONDATE1,
        ZACCOUNT, ZACCOUNT8, ZFOLDER, ZPARENT, ZNOTE, ZMEDIA, ZNOTEDATA,
        ZTYPEUTI, ZSUMMARY, ZOCRSUMMARY, ZHANDWRITINGSUMMARY, ZURLSTRING,
        ZMERGEABLEDATA, ZMERGEABLEDATA1, ZFILENAME
      ) VALUES (?1,?2,1,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23,?24,?25,?26,?27,?28)",
      params![
        row.pk,
        row.ent,
        row.identifier,
        row.name,
        row.title,
        row.title1,
        row.title2,
        row.snippet,
        row.pinned,
        row.creation,
        row.creation1,
        row.modification,
        row.modification1,
        row.account,
        row.account8,
        row.folder,
        row.parent,
        row.note,
        row.media,
        row.note_data,
        row.type_uti,
        row.summary,
        row.ocr,
        row.handwriting,
        row.url,
        row.mergeable,
        row.mergeable1,
        row.filename
      ],
    )
    .expect("insert object");
}

fn insert_data(conn: &Connection, pk: i64, data: Option<Vec<u8>>, tag: Option<Vec<u8>>) {
  conn
    .execute(
      "INSERT INTO ZICNOTEDATA (Z_PK, Z_ENT, Z_OPT, ZDATA, ZCRYPTOTAG) VALUES (?1, 19, 1, ?2, ?3)",
      params![pk, data, tag],
    )
    .expect("insert note data");
}

fn plain_note(text: &str) -> Vec<u8> {
  note_message(text, Vec::new()).encode_to_vec()
}

fn rich_note() -> Vec<u8> {
  let uuid = sample_uuid();
  note_message(
    "Hello\u{FFFC}",
    vec![AttributeRun {
      length: Some(6),
      paragraph_style: Some(ParagraphStyle {
        style: Some(1),
        alignment: Some(2),
        writing_direction: Some(1),
        indent: Some(3),
        todo: Some(Todo {
          uuid: Some(uuid.clone()),
          done: Some(true),
        }),
        block_quote_level: Some(0),
        uuid: Some(uuid),
      }),
      font: Some(Font {
        font_name: Some("Helvetica".into()),
        point_size: Some(12.0),
        font_hints: Some(1),
      }),
      font_weight: Some(6),
      underlined: Some(1),
      strikethrough: Some(0),
      superscript: Some(-1),
      link: Some("https://example.com".into()),
      color: Some(Color {
        red: Some(1.0),
        green: Some(0.0),
        blue: Some(0.5),
        alpha: Some(1.0),
      }),
      attachment_info: Some(AttachmentInfo {
        attachment_identifier: Some("ATT-1".into()),
        type_uti: Some("public.png".into()),
      }),
      timestamp: Some(0),
      emphasis: Some(2),
    }],
  )
  .encode_to_vec()
}

pub(super) fn attachment_body_blob(attachments: &[(&str, &str)]) -> Vec<u8> {
  gzip(&attachment_document(attachments))
}

fn attachment_document(attachments: &[(&str, &str)]) -> Vec<u8> {
  let mut text = String::new();
  let mut runs = Vec::new();
  for (identifier, uti) in attachments {
    text.push('\u{FFFC}');
    runs.push(AttributeRun {
      length: Some(1),
      attachment_info: Some(AttachmentInfo {
        attachment_identifier: Some((*identifier).to_string()),
        type_uti: Some((*uti).to_string()),
      }),
      ..AttributeRun::default()
    });
  }
  note_message(&text, runs).encode_to_vec()
}

fn note_message(text: &str, runs: Vec<AttributeRun>) -> NoteDocument {
  NoteDocument {
    version: Some(NoteVersion {
      serialization_version: Some(0),
      minimum_supported_version: Some(0),
      data: Some(TopotextString {
        string: Some(text.into()),
        attribute_run: runs,
      }),
    }),
  }
}

fn sample_uuid() -> Vec<u8> {
  vec![
    0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
  ]
}

fn rtl_table_blob() -> Vec<u8> {
  let row_uuid = vec![1u8; 16];
  let left = vec![2u8; 16];
  let right = vec![3u8; 16];
  let proto = MergableDataProto {
    object: Some(MergableDataObject {
      version: Some(0),
      data: Some(MergeableDataObjectData {
        entry: vec![
          entry_map(
            0,
            vec![
              map_entry(1, object_index(1)),
              map_entry(2, object_index(2)),
              map_entry(3, object_index(3)),
            ],
          ),
          entry_rows(vec![(0, row_uuid.clone())]),
          entry_columns(vec![(0, left.clone()), (1, right.clone())]),
          entry_dict(vec![
            (object_index(4), object_index(6)),
            (object_index(5), object_index(7)),
          ]),
          entry_uuid_index(1),
          entry_uuid_index(2),
          entry_dict(vec![(object_index(13), object_index(9))]),
          entry_dict(vec![(object_index(13), object_index(10))]),
          entry_uuid_index(0),
          entry_note("Left"),
          entry_note("Right"),
          entry_direction(1, "CRTableColumnDirectionRightToLeft"),
          MergeableDataObjectEntry::default(),
          entry_uuid_index(7),
        ],
        key_item: vec![
          "crTableColumnDirection".into(),
          "crRows".into(),
          "crColumns".into(),
          "cellColumns".into(),
        ],
        type_item: vec!["com.apple.notes.ICTable".into()],
        uuid_item: vec![row_uuid, left, right],
      }),
    }),
  };
  gzip(&proto.encode_to_vec())
}

fn entry_rows(attachments: Vec<(i32, Vec<u8>)>) -> MergeableDataObjectEntry {
  MergeableDataObjectEntry {
    ordered_set: Some(OrderedSet {
      ordering: Some(OrderedSetOrdering {
        array: Some(attachment_array(attachments)),
        contents: Some(Dictionary {
          element: vec![DictionaryElement {
            key: Some(object_index(8)),
            value: Some(object_index(13)),
          }],
        }),
      }),
      elements: None,
    }),
    ..MergeableDataObjectEntry::default()
  }
}

fn entry_columns(attachments: Vec<(i32, Vec<u8>)>) -> MergeableDataObjectEntry {
  MergeableDataObjectEntry {
    ordered_set: Some(OrderedSet {
      ordering: Some(OrderedSetOrdering {
        array: Some(attachment_array(attachments)),
        contents: None,
      }),
      elements: None,
    }),
    ..MergeableDataObjectEntry::default()
  }
}

fn attachment_array(attachments: Vec<(i32, Vec<u8>)>) -> OrderedSetOrderingArray {
  OrderedSetOrderingArray {
    contents: None,
    attachment: attachments
      .into_iter()
      .map(|(index, uuid)| OrderedSetOrderingArrayAttachment {
        index: Some(index),
        uuid,
      })
      .collect(),
  }
}

fn entry_map(type_index: i32, map_entry: Vec<MapEntry>) -> MergeableDataObjectEntry {
  MergeableDataObjectEntry {
    custom_map: Some(MergeableDataObjectMap {
      type_index: Some(type_index),
      map_entry,
    }),
    ..MergeableDataObjectEntry::default()
  }
}

fn entry_dict(pairs: Vec<(ObjectId, ObjectId)>) -> MergeableDataObjectEntry {
  MergeableDataObjectEntry {
    dictionary: Some(Dictionary {
      element: pairs
        .into_iter()
        .map(|(key, value)| DictionaryElement {
          key: Some(key),
          value: Some(value),
        })
        .collect(),
    }),
    ..MergeableDataObjectEntry::default()
  }
}

fn entry_uuid_index(index: u64) -> MergeableDataObjectEntry {
  MergeableDataObjectEntry {
    custom_map: Some(MergeableDataObjectMap {
      type_index: None,
      map_entry: vec![map_entry(
        4,
        ObjectId {
          unsigned_integer_value: Some(index),
          string_value: None,
          object_index: None,
        },
      )],
    }),
    ..MergeableDataObjectEntry::default()
  }
}

fn entry_direction(key: i32, text: &str) -> MergeableDataObjectEntry {
  MergeableDataObjectEntry {
    custom_map: Some(MergeableDataObjectMap {
      type_index: None,
      map_entry: vec![map_entry(
        key,
        ObjectId {
          unsigned_integer_value: None,
          string_value: Some(text.into()),
          object_index: None,
        },
      )],
    }),
    ..MergeableDataObjectEntry::default()
  }
}

fn entry_note(text: &str) -> MergeableDataObjectEntry {
  MergeableDataObjectEntry {
    note: Some(TopotextString {
      string: Some(text.into()),
      attribute_run: Vec::new(),
    }),
    ..MergeableDataObjectEntry::default()
  }
}

fn map_entry(key: i32, value: ObjectId) -> MapEntry {
  MapEntry {
    key: Some(key),
    value: Some(value),
  }
}

fn object_index(index: i32) -> ObjectId {
  ObjectId {
    unsigned_integer_value: None,
    string_value: None,
    object_index: Some(index),
  }
}

fn gzip(data: &[u8]) -> Vec<u8> {
  let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
  encoder.write_all(data).unwrap();
  encoder.finish().unwrap()
}

fn zlib(data: &[u8]) -> Vec<u8> {
  let mut encoder = ZlibEncoder::new(Vec::new(), Compression::new(6));
  encoder.write_all(data).unwrap();
  encoder.finish().unwrap()
}

fn temp_db() -> TmpDb {
  static NEXT: AtomicU64 = AtomicU64::new(0);
  let mut path = std::env::temp_dir();
  path.push(format!(
    "abridge-notes-{}-{}.sqlite",
    std::process::id(),
    NEXT.fetch_add(1, Ordering::Relaxed)
  ));
  TmpDb(path)
}

pub(super) fn add_recently_deleted(store: &Path) {
  let conn = Connection::open(store).expect("fixture db");
  conn
    .execute_batch(
      "
      ALTER TABLE ZICCLOUDSYNCINGOBJECT ADD COLUMN ZFOLDERTYPE INTEGER;
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE2, ZACCOUNT8, ZFOLDERTYPE)
        VALUES (90, 2, 'trash-1', 'Recently Deleted', 1, 1);
      INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, Z_ENT, ZIDENTIFIER, ZTITLE1, ZACCOUNT, ZFOLDER)
        VALUES (91, 3, 'note-trashed', 'Old', 1, 90);
      ",
    )
    .expect("trash rows");
}

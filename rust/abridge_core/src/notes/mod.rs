//! Apple Notes provider. Reads the local store; writes go through Notes JXA.

mod attachment_file;
mod attributes;
mod columns;
mod confirm;
mod decode;
mod error;
mod markdown;
mod markdown_html;
mod note_attributes;
mod osascript;
mod pdf_text;
mod project;
mod proto_note;
mod proto_table;
mod query;
mod resolve;
mod rows;
mod script;
mod search;
mod shape;
mod store;
mod table;
mod timefmt;
mod write;
mod write_folder;

use serde_json::Value;
use std::path::Path;

pub use error::NotesError;
pub(crate) use resolve::{ACCOUNT_ONLY_WITH_PATH, CREATE_FOLDER_PARENT, FOLDER_EXACTLY_ONE, NOTE_EXACTLY_ONE};

/// A tool result: the JSON payload, plus the attachment file `get_attachment` reads.
#[derive(Debug)]
pub struct NotesOutput {
  pub payload: Value,
  pub file: Option<AttachmentFile>,
}

#[derive(Debug)]
pub struct AttachmentFile {
  pub bytes: Vec<u8>,
  pub mime_type: &'static str,
  pub uri: String,
}

pub fn call(operation: &str, arguments: &Value) -> Result<NotesOutput, NotesError> {
  call_output(&default_store_path(), operation, arguments)
}

pub(crate) fn call_output(path: &Path, operation: &str, arguments: &Value) -> Result<NotesOutput, NotesError> {
  if operation == "get_attachment" {
    return attachment_file::get_attachment(path, arguments);
  }
  call_with_store(path, operation, arguments).map(|payload| NotesOutput { payload, file: None })
}

pub fn call_with_store(path: &Path, operation: &str, arguments: &Value) -> Result<Value, NotesError> {
  match operation {
    "list_folders" => query::list_folders(path, arguments),
    "list_notes" => query::list_notes(path, arguments),
    "get_note" => query::get_note(path, arguments),
    "search_notes" => search::search_notes(path, arguments),
    "create_note" => write::create_note(path, arguments),
    "update_note" => write::update_note(path, arguments),
    "move_note" => write::move_note(path, arguments),
    "delete_note" => write::delete_note(path, arguments),
    "create_folder" => write_folder::create_folder(path, arguments),
    "delete_folder" => write_folder::delete_folder(path, arguments),
    _ => Err(NotesError::new(
      "notes_error",
      format!("unknown notes operation: {operation}"),
    )),
  }
}

pub fn default_store_path() -> std::path::PathBuf {
  store_path_for_home(&std::env::var("HOME").unwrap_or_default())
}

pub fn store_path_for_home(home: &str) -> std::path::PathBuf {
  Path::new(home).join("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
}

#[cfg(test)]
mod attachment_fixture;
#[cfg(test)]
mod attachment_tests;
#[cfg(test)]
mod fixture;
#[cfg(test)]
mod tests;

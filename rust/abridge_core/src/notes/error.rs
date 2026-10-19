//! Notes tool errors returned inside the MCP `isError` envelope.

use serde_json::Value;

#[derive(Debug, PartialEq, Eq, thiserror::Error)]
#[error("{message}")]
pub struct NotesError {
  pub code: &'static str,
  pub message: String,
}

impl NotesError {
  pub(crate) fn new(code: &'static str, message: impl Into<String>) -> Self {
    Self {
      code,
      message: message.into(),
    }
  }

  pub(crate) fn json_text(&self) -> String {
    self.json().to_string()
  }

  pub(crate) fn json(&self) -> Value {
    serde_json::json!({ "code": self.code, "message": self.message })
  }
}

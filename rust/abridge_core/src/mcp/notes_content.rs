//! MCP `content` for Notes tool results: the JSON payload as text, then an attachment file
//! when the tool read one. Files a model can view go as `image` content; anything else goes as
//! an embedded resource, so a client never forwards an image the model rejects.

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde_json::{Value, json};

use crate::notes::{AttachmentFile, NotesError, NotesOutput};
use crate::rendition::{MODEL_IMAGE_MAX_BASE64, MODEL_IMAGE_TYPES};

pub(super) fn content(outcome: Result<NotesOutput, NotesError>) -> (bool, Vec<Value>) {
  match outcome {
    Ok(output) => {
      let mut content = vec![json!({ "type": "text", "text": output.payload.to_string() })];
      content.extend(output.file.map(file_content));
      (false, content)
    }
    Err(error) => (true, vec![json!({ "type": "text", "text": error.json_text() })]),
  }
}

fn file_content(file: AttachmentFile) -> Value {
  let data = STANDARD.encode(&file.bytes);
  if MODEL_IMAGE_TYPES.contains(&file.mime_type) && data.len() <= MODEL_IMAGE_MAX_BASE64 {
    json!({ "type": "image", "data": data, "mimeType": file.mime_type })
  } else {
    json!({
      "type": "resource",
      "resource": { "uri": file.uri, "mimeType": file.mime_type, "blob": data }
    })
  }
}

#[cfg(test)]
mod tests {
  use super::content;
  use crate::notes::{AttachmentFile, NotesError, NotesOutput};
  use crate::rendition::MODEL_IMAGE_MAX_BASE64;
  use serde_json::json;

  fn with_file(mime_type: &'static str) -> NotesOutput {
    with_bytes(mime_type, b"hi".to_vec())
  }

  fn with_bytes(mime_type: &'static str, bytes: Vec<u8>) -> NotesOutput {
    NotesOutput {
      payload: json!({ "identifier": "att-1" }),
      file: Some(AttachmentFile {
        bytes,
        mime_type,
        uri: "file:///a/b".into(),
      }),
    }
  }

  #[test]
  fn images_over_the_model_limit_become_embedded_resources() {
    // 3 raw bytes encode to 4 base64 bytes, so this lands exactly on the limit.
    let at_limit = vec![0; MODEL_IMAGE_MAX_BASE64 / 4 * 3];
    assert_eq!(content(Ok(with_bytes("image/jpeg", at_limit))).1[1]["type"], "image");
    let over = vec![0; MODEL_IMAGE_MAX_BASE64 / 4 * 3 + 1];
    assert_eq!(content(Ok(with_bytes("image/jpeg", over))).1[1]["type"], "resource");
  }

  #[test]
  fn model_images_become_image_content_and_other_files_embedded_resources() {
    let (is_error, image) = content(Ok(with_file("image/png")));
    assert!(!is_error);
    assert_eq!(image[0]["text"], r#"{"identifier":"att-1"}"#);
    assert_eq!(
      image[1],
      json!({ "type": "image", "data": "aGk=", "mimeType": "image/png" })
    );

    let (_, heic) = content(Ok(with_file("image/heic")));
    assert_eq!(
      heic[1],
      json!({
        "type": "resource",
        "resource": { "uri": "file:///a/b", "mimeType": "image/heic", "blob": "aGk=" }
      })
    );
  }

  #[test]
  fn errors_and_file_less_results_are_one_text_item() {
    let (is_error, error) = content(Err(NotesError::new("not_found", "attachment not found")));
    assert!(is_error);
    assert_eq!(error.len(), 1);
    let plain = NotesOutput {
      payload: json!([]),
      file: None,
    };
    assert_eq!(content(Ok(plain)).1.len(), 1);
  }
}

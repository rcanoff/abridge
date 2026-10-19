//! Gzip/zlib inflation and topotext JSON.

use flate2::read::{GzDecoder, ZlibDecoder};
use prost::Message;
use serde_json::{Number, Value};
use std::io::Read;

use super::proto_note::{
  AttachmentInfo, AttributeRun, Color, Font, NoteDocument, ParagraphStyle, Todo, TopotextString,
};
use super::timefmt;

/// Upper bound for one inflated blob. Note bodies and tables are kilobytes to a few megabytes;
/// anything past this is malformed and would otherwise exhaust the host's memory.
const MAX_INFLATED_BYTES: u64 = 64 * 1024 * 1024;

pub(crate) fn inflate(blob: &[u8]) -> Option<Vec<u8>> {
  if blob.starts_with(&[0x1f, 0x8b]) {
    read_bounded(GzDecoder::new(blob))
  } else if is_zlib_header(blob) {
    read_bounded(ZlibDecoder::new(blob))
  } else {
    None
  }
}

/// RFC 1950: deflate method (CM = 8) and a header checksum divisible by 31. Covers every
/// compression level (`78 01`, `78 5e`, `78 9c`, `78 da`).
fn is_zlib_header(blob: &[u8]) -> bool {
  match blob {
    [cmf, flg, ..] => cmf & 0x0f == 8 && (u16::from(*cmf) << 8 | u16::from(*flg)) % 31 == 0,
    _ => false,
  }
}

fn read_bounded(reader: impl Read) -> Option<Vec<u8>> {
  let mut output = Vec::new();
  reader.take(MAX_INFLATED_BYTES + 1).read_to_end(&mut output).ok()?;
  if output.len() as u64 > MAX_INFLATED_BYTES {
    tracing::debug!("notes blob exceeds the inflate limit");
    return None;
  }
  Some(output)
}

pub(crate) fn decode_note_blob(blob: &[u8]) -> Option<Value> {
  let Some(raw) = inflate(blob) else {
    tracing::debug!("note body compression decode failed");
    return None;
  };
  let document = match NoteDocument::decode(raw.as_slice()) {
    Ok(document) => document,
    Err(err) => {
      tracing::debug!(error = %err, "note body decode failed");
      return None;
    }
  };
  let Some(text) = document.version.as_ref().and_then(|version| version.data.as_ref()) else {
    tracing::debug!("note body decode produced no text");
    return None;
  };
  Some(topotext_json(text))
}

pub(crate) fn topotext_json(text: &TopotextString) -> Value {
  serde_json::json!({
    "string": text.string,
    "attribute_runs": text.attribute_run.iter().map(attribute_run_json).collect::<Vec<_>>(),
  })
}

fn attribute_run_json(run: &AttributeRun) -> Value {
  serde_json::json!({
    "length": run.length,
    "paragraph_style": run.paragraph_style.as_ref().map(paragraph_style_json),
    "font": run.font.as_ref().map(font_json),
    "font_weight": run.font_weight,
    "underlined": run.underlined,
    "strikethrough": run.strikethrough,
    "superscript": run.superscript,
    "link": run.link,
    "color": run.color.as_ref().map(color_json),
    "attachment_info": run.attachment_info.as_ref().map(attachment_info_json),
    "timestamp": run.timestamp.and_then(timefmt::unix_secs_to_rfc3339),
    "emphasis": run.emphasis,
  })
}

fn paragraph_style_json(style: &ParagraphStyle) -> Value {
  serde_json::json!({
    "style": style.style,
    "alignment": style.alignment,
    "writing_direction": style.writing_direction,
    "indent": style.indent,
    "todo": style.todo.as_ref().map(todo_json),
    "block_quote_level": style.block_quote_level,
    "uuid": style.uuid.as_deref().and_then(format_uuid),
  })
}

fn todo_json(todo: &Todo) -> Value {
  serde_json::json!({
    "uuid": todo.uuid.as_deref().and_then(format_uuid),
    "done": todo.done,
  })
}

fn font_json(font: &Font) -> Value {
  serde_json::json!({
    "font_name": font.font_name,
    "point_size": float_value(font.point_size),
    "font_hints": font.font_hints,
  })
}

fn color_json(color: &Color) -> Value {
  serde_json::json!({
    "red": float_value(color.red),
    "green": float_value(color.green),
    "blue": float_value(color.blue),
    "alpha": float_value(color.alpha),
  })
}

fn attachment_info_json(info: &AttachmentInfo) -> Value {
  serde_json::json!({
    "attachment_identifier": info.attachment_identifier,
    "type_uti": info.type_uti,
  })
}

fn float_value(value: Option<f32>) -> Value {
  value
    .and_then(|number| Number::from_f64(f64::from(number)).map(Value::Number))
    .unwrap_or(Value::Null)
}

pub(crate) fn format_uuid(bytes: &[u8]) -> Option<String> {
  if bytes.len() != 16 {
    return None;
  }
  Some(format!(
    "{:02X}{:02X}{:02X}{:02X}-{:02X}{:02X}-{:02X}{:02X}-{:02X}{:02X}-{:02X}{:02X}{:02X}{:02X}{:02X}{:02X}",
    bytes[0],
    bytes[1],
    bytes[2],
    bytes[3],
    bytes[4],
    bytes[5],
    bytes[6],
    bytes[7],
    bytes[8],
    bytes[9],
    bytes[10],
    bytes[11],
    bytes[12],
    bytes[13],
    bytes[14],
    bytes[15]
  ))
}

#[cfg(test)]
mod tests {
  use super::{MAX_INFLATED_BYTES, inflate};
  use flate2::Compression;
  use flate2::write::{GzEncoder, ZlibEncoder};
  use std::io::Write;

  fn zlib(data: &[u8], level: u32) -> Vec<u8> {
    let mut encoder = ZlibEncoder::new(Vec::new(), Compression::new(level));
    encoder.write_all(data).expect("write");
    encoder.finish().expect("finish")
  }

  #[test]
  fn inflates_zlib_at_every_compression_level() {
    for level in [0, 1, 6, 9] {
      let blob = zlib(b"hello notes", level);
      assert_eq!(inflate(&blob).as_deref(), Some(&b"hello notes"[..]), "level {level}");
    }
    assert_eq!(inflate(b"\x78\x00not zlib"), None);
  }

  #[test]
  fn refuses_blobs_that_inflate_past_the_limit() {
    let mut encoder = GzEncoder::new(Vec::new(), Compression::best());
    let chunk = vec![0u8; 1024 * 1024];
    for _ in 0..=(MAX_INFLATED_BYTES / chunk.len() as u64) {
      encoder.write_all(&chunk).expect("write");
    }
    let bomb = encoder.finish().expect("finish");
    assert_eq!(inflate(&bomb), None);
  }
}

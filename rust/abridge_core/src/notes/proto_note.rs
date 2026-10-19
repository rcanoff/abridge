//! Hand-written Notes protobuf messages (no protoc).
//!
//! Wire layout checked against a Notes store: outer field 2 is `versioned_document.Version`,
//! whose field 3 is `topotext.String`.

use prost::Message;

#[derive(Clone, PartialEq, Message)]
pub(crate) struct NoteDocument {
  #[prost(message, optional, tag = "2")]
  pub version: Option<NoteVersion>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct NoteVersion {
  #[prost(uint64, optional, tag = "1")]
  pub serialization_version: Option<u64>,
  #[prost(uint64, optional, tag = "2")]
  pub minimum_supported_version: Option<u64>,
  #[prost(message, optional, tag = "3")]
  pub data: Option<TopotextString>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct TopotextString {
  #[prost(string, optional, tag = "2")]
  pub string: Option<String>,
  #[prost(message, repeated, tag = "5")]
  pub attribute_run: Vec<AttributeRun>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct AttributeRun {
  #[prost(int32, optional, tag = "1")]
  pub length: Option<i32>,
  #[prost(message, optional, tag = "2")]
  pub paragraph_style: Option<ParagraphStyle>,
  #[prost(message, optional, tag = "3")]
  pub font: Option<Font>,
  #[prost(int32, optional, tag = "5")]
  pub font_weight: Option<i32>,
  #[prost(int32, optional, tag = "6")]
  pub underlined: Option<i32>,
  #[prost(int32, optional, tag = "7")]
  pub strikethrough: Option<i32>,
  #[prost(int32, optional, tag = "8")]
  pub superscript: Option<i32>,
  #[prost(string, optional, tag = "9")]
  pub link: Option<String>,
  #[prost(message, optional, tag = "10")]
  pub color: Option<Color>,
  #[prost(message, optional, tag = "12")]
  pub attachment_info: Option<AttachmentInfo>,
  #[prost(int64, optional, tag = "13")]
  pub timestamp: Option<i64>,
  #[prost(int32, optional, tag = "14")]
  pub emphasis: Option<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct ParagraphStyle {
  #[prost(int32, optional, tag = "1")]
  pub style: Option<i32>,
  #[prost(int32, optional, tag = "2")]
  pub alignment: Option<i32>,
  #[prost(int32, optional, tag = "3")]
  pub writing_direction: Option<i32>,
  #[prost(int32, optional, tag = "4")]
  pub indent: Option<i32>,
  #[prost(message, optional, tag = "5")]
  pub todo: Option<Todo>,
  #[prost(int32, optional, tag = "8")]
  pub block_quote_level: Option<i32>,
  #[prost(bytes, optional, tag = "9")]
  pub uuid: Option<Vec<u8>>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct Todo {
  #[prost(bytes, optional, tag = "1")]
  pub uuid: Option<Vec<u8>>,
  #[prost(bool, optional, tag = "2")]
  pub done: Option<bool>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct Font {
  #[prost(string, optional, tag = "1")]
  pub font_name: Option<String>,
  #[prost(float, optional, tag = "2")]
  pub point_size: Option<f32>,
  #[prost(int32, optional, tag = "3")]
  pub font_hints: Option<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct Color {
  #[prost(float, optional, tag = "1")]
  pub red: Option<f32>,
  #[prost(float, optional, tag = "2")]
  pub green: Option<f32>,
  #[prost(float, optional, tag = "3")]
  pub blue: Option<f32>,
  #[prost(float, optional, tag = "4")]
  pub alpha: Option<f32>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct AttachmentInfo {
  #[prost(string, optional, tag = "1")]
  pub attachment_identifier: Option<String>,
  #[prost(string, optional, tag = "2")]
  pub type_uti: Option<String>,
}

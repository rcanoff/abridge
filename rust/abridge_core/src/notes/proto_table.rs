//! Hand-written mergeable-table protobuf messages (no protoc).
//!
//! Field numbers follow Notes' `MergableDataProto` CRDT. Unknown fields are ignored.

use prost::Message;

use super::proto_note::TopotextString;

#[derive(Clone, PartialEq, Message)]
pub(crate) struct MergableDataProto {
  #[prost(message, optional, tag = "2")]
  pub object: Option<MergableDataObject>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct MergableDataObject {
  #[prost(int32, optional, tag = "2")]
  pub version: Option<i32>,
  #[prost(message, optional, tag = "3")]
  pub data: Option<MergeableDataObjectData>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct MergeableDataObjectData {
  #[prost(message, repeated, tag = "3")]
  pub entry: Vec<MergeableDataObjectEntry>,
  #[prost(string, repeated, tag = "4")]
  pub key_item: Vec<String>,
  #[prost(string, repeated, tag = "5")]
  pub type_item: Vec<String>,
  #[prost(bytes, repeated, tag = "6")]
  pub uuid_item: Vec<Vec<u8>>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct MergeableDataObjectEntry {
  #[prost(message, optional, tag = "6")]
  pub dictionary: Option<Dictionary>,
  #[prost(message, optional, tag = "10")]
  pub note: Option<TopotextString>,
  #[prost(message, optional, tag = "13")]
  pub custom_map: Option<MergeableDataObjectMap>,
  #[prost(message, optional, tag = "16")]
  pub ordered_set: Option<OrderedSet>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct Dictionary {
  #[prost(message, repeated, tag = "1")]
  pub element: Vec<DictionaryElement>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct DictionaryElement {
  #[prost(message, optional, tag = "1")]
  pub key: Option<ObjectId>,
  #[prost(message, optional, tag = "2")]
  pub value: Option<ObjectId>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct ObjectId {
  #[prost(uint64, optional, tag = "2")]
  pub unsigned_integer_value: Option<u64>,
  #[prost(string, optional, tag = "4")]
  pub string_value: Option<String>,
  #[prost(int32, optional, tag = "6")]
  pub object_index: Option<i32>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct MergeableDataObjectMap {
  #[prost(int32, optional, tag = "1")]
  pub type_index: Option<i32>,
  #[prost(message, repeated, tag = "3")]
  pub map_entry: Vec<MapEntry>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct MapEntry {
  #[prost(int32, optional, tag = "1")]
  pub key: Option<i32>,
  #[prost(message, optional, tag = "2")]
  pub value: Option<ObjectId>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct OrderedSet {
  #[prost(message, optional, tag = "1")]
  pub ordering: Option<OrderedSetOrdering>,
  #[prost(message, optional, tag = "2")]
  pub elements: Option<Dictionary>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct OrderedSetOrdering {
  #[prost(message, optional, tag = "1")]
  pub array: Option<OrderedSetOrderingArray>,
  #[prost(message, optional, tag = "2")]
  pub contents: Option<Dictionary>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct OrderedSetOrderingArray {
  #[prost(message, optional, tag = "1")]
  pub contents: Option<TopotextString>,
  #[prost(message, repeated, tag = "2")]
  pub attachment: Vec<OrderedSetOrderingArrayAttachment>,
}

#[derive(Clone, PartialEq, Message)]
pub(crate) struct OrderedSetOrderingArrayAttachment {
  #[prost(int32, optional, tag = "1")]
  pub index: Option<i32>,
  #[prost(bytes, tag = "2")]
  pub uuid: Vec<u8>,
}

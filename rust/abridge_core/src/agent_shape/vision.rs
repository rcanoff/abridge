//! Vision results keep the text, barcodes, and landmarks. Masks, pixel buffers, and request metadata go.

use serde_json::Value;

use super::util;

const DROP: &[&str] = &[
  "uuid",
  "request_revision",
  "originating_request_descriptor",
  "global_segmentation_mask",
  "pixel_buffer",
  "time_range",
  "payload_data",
  "supplemental_payload_data",
  "all_points",
  "precision_estimates_per_point",
  "top_left",
  "top_right",
  "bottom_left",
  "bottom_right",
  "feature_name",
];

pub(crate) fn shape(value: &Value) -> Value {
  util::slim_dropping(value, DROP).unwrap_or(Value::Object(serde_json::Map::new()))
}

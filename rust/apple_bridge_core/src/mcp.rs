//! Stub MCP HTTP handler until full JSON-RPC protocol lands.

use axum::{Json, http::StatusCode, response::IntoResponse};
use serde_json::json;

pub async fn handle_mcp() -> impl IntoResponse {
  (
    StatusCode::NOT_IMPLEMENTED,
    Json(json!({
      "error": "not_implemented",
      "message": "MCP protocol handler not yet implemented"
    })),
  )
}

//! HTTP routes for the embedded MCP server.
//!
//! `GET /health` returns `{"ok": true}` as the liveness contract for PR 2b.

use axum::{Json, Router, routing::get};
use serde_json::{Value, json};

async fn health() -> Json<Value> {
  Json(json!({ "ok": true }))
}

pub fn router() -> Router {
  Router::new().route("/health", get(health))
}

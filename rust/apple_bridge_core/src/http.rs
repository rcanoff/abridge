//! HTTP routes for the embedded MCP server.
//!
//! `GET /health` returns `{"ok": true}` as the liveness contract for PR 2b.

use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

async fn health() -> Json<Value> {
  Json(json!({ "ok": true }))
}

pub fn router() -> Router {
  Router::new().route("/health", get(health))
}
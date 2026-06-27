//! HTTP routes for the embedded MCP server.
//!
//! `GET /health` is public. `POST /mcp` requires bearer auth (PR 2d).

use std::sync::Arc;

use axum::{
  Router, middleware,
  routing::{get, post},
};

use crate::{auth, mcp};

async fn health() -> axum::Json<serde_json::Value> {
  axum::Json(serde_json::json!({ "ok": true }))
}

pub fn router(bearer_token: String) -> Router {
  let public = Router::new().route("/health", get(health));

  let protected = Router::new()
    .route("/mcp", post(mcp::handle_mcp))
    .layer(middleware::from_fn_with_state(
      Arc::new(bearer_token),
      auth::require_bearer,
    ));

  public.merge(protected)
}

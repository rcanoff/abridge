//! HTTP routes for the embedded MCP server.
//!
//! `GET /health` is public. `POST /mcp` requires bearer auth (PR 2d).

use std::sync::Arc;

use axum::{
  Router, middleware,
  routing::{get, post},
};

use crate::{auth, mcp::McpState};

async fn health() -> axum::Json<serde_json::Value> {
  axum::Json(serde_json::json!({ "ok": true }))
}

pub fn router(state: McpState) -> Router {
  let bearer_token = Arc::new(state.bearer_token.clone());
  let public = Router::new().route("/health", get(health));

  let protected = Router::new()
    .route("/mcp", post(crate::mcp::handle_mcp))
    .with_state(state)
    .layer(middleware::from_fn_with_state(bearer_token, auth::require_bearer));

  public.merge(protected)
}

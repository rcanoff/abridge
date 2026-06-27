use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

async fn health() -> Json<Value> {
  Json(json!({ "ok": true }))
}

pub fn router() -> Router {
  Router::new().route("/health", get(health))
}
//! Bearer token parsing and validation for authenticated HTTP routes.

use axum::{
  Json,
  extract::State,
  http::{Request, StatusCode, header::WWW_AUTHENTICATE},
  middleware::Next,
  response::{IntoResponse, Response},
};
use serde_json::json;
use std::sync::Arc;

pub fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
  if left.len() != right.len() {
    return false;
  }

  let mut diff = 0u8;
  for (a, b) in left.iter().zip(right.iter()) {
    diff |= a ^ b;
  }
  diff == 0
}

pub fn parse_bearer_token(header_value: &str) -> Option<&str> {
  let trimmed = header_value.trim();
  let (scheme, token) = trimmed.split_once(' ')?;
  if !scheme.eq_ignore_ascii_case("bearer") {
    return None;
  }

  let token = token.trim();
  if token.is_empty() {
    return None;
  }

  Some(token)
}

pub fn unauthorized_response() -> Response {
  (
    StatusCode::UNAUTHORIZED,
    [(WWW_AUTHENTICATE, "Bearer")],
    Json(json!({
      "error": "unauthorized",
      "message": "missing or invalid bearer token"
    })),
  )
    .into_response()
}

pub async fn require_bearer(
  State(expected_token): State<Arc<String>>,
  request: Request<axum::body::Body>,
  next: Next,
) -> Response {
  let authorized = request
    .headers()
    .get(http::header::AUTHORIZATION)
    .and_then(|value| value.to_str().ok())
    .and_then(parse_bearer_token)
    .is_some_and(|provided| constant_time_eq(provided.as_bytes(), expected_token.as_bytes()));

  if authorized {
    next.run(request).await
  } else {
    unauthorized_response()
  }
}

#[cfg(test)]
mod tests {
  use super::{constant_time_eq, parse_bearer_token};

  #[test]
  fn parse_bearer_accepts_standard_header() {
    assert_eq!(parse_bearer_token("Bearer secret-token"), Some("secret-token"));
  }

  #[test]
  fn parse_bearer_rejects_missing_scheme() {
    assert_eq!(parse_bearer_token("secret-token"), None);
  }

  #[test]
  fn parse_bearer_rejects_empty_token() {
    assert_eq!(parse_bearer_token("Bearer "), None);
  }

  #[test]
  fn constant_time_eq_matches_equal_strings() {
    assert!(constant_time_eq(b"abc", b"abc"));
  }

  #[test]
  fn constant_time_eq_rejects_different_lengths() {
    assert!(!constant_time_eq(b"abc", b"abcd"));
  }
}

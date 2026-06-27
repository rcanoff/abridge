#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
  #[error("invalid configuration: {message}")]
  InvalidConfig { message: String },

  #[error("server is already running")]
  AlreadyRunning,

  #[error("server state unavailable")]
  StateUnavailable,

  #[error("failed to bind server: {message}")]
  BindFailed { message: String },

  #[error("failed to create runtime: {message}")]
  RuntimeFailed { message: String },

  #[error("server start was cancelled")]
  StartCancelled,
}
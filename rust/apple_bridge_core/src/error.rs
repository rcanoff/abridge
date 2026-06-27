#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
  #[error("invalid configuration: {message}")]
  InvalidConfig { message: String },

  #[error("server is already running")]
  AlreadyRunning,

  #[error("server state unavailable")]
  StateUnavailable,
}
mod config;
mod diagnostics;
mod error;
mod logging;

pub use config::{
  ProviderConfig, ProviderRequest, ProviderResponse, ServerConfig, validate_config,
};
pub use diagnostics::{ProviderStatus, ServerStatus};
pub use error::CoreError;

#[uniffi::export]
pub fn init_logging() {
  logging::init_logging();
}

uniffi::setup_scaffolding!();
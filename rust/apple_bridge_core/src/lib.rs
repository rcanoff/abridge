use std::sync::Arc;

mod config;
mod diagnostics;
mod error;
mod http;
mod logging;
mod providers;
mod server;

pub use config::{ProviderConfig, ProviderRequest, ProviderResponse, ServerConfig, validate_config};
pub use diagnostics::{ProviderStatus, ServerStatus};
pub use error::CoreError;
pub use providers::ProviderBridge;
pub use server::ServerHandle;

#[uniffi::export]
pub fn init_logging() {
  logging::init_logging();
}

#[uniffi::export]
pub fn create_server(config: ServerConfig, provider: Box<dyn ProviderBridge>) -> Result<Arc<ServerHandle>, CoreError> {
  server::create_server(config, provider)
}

#[uniffi::export]
pub fn start_server(handle: Arc<ServerHandle>) -> Result<(), CoreError> {
  handle.start()
}

#[uniffi::export]
pub fn stop_server(handle: Arc<ServerHandle>) -> Result<(), CoreError> {
  handle.stop()
}

#[uniffi::export]
pub fn server_status(handle: Arc<ServerHandle>) -> ServerStatus {
  handle.status()
}

uniffi::setup_scaffolding!();

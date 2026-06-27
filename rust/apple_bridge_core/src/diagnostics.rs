#[derive(Debug, Clone, uniffi::Record)]
pub struct ProviderStatus {
  pub name: String,
  pub enabled: bool,
  pub healthy: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ServerStatus {
  pub running: bool,
  pub bound_host: String,
  pub bound_port: u16,
  pub provider_statuses: Vec<ProviderStatus>,
  pub last_error: Option<String>,
}

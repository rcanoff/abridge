use crate::config::{ProviderRequest, ProviderResponse};

#[uniffi::export(callback_interface)]
pub trait ProviderBridge: Send + Sync {
  fn call_provider(&self, request: ProviderRequest) -> ProviderResponse;
}

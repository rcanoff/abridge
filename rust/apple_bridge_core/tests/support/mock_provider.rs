use apple_bridge_core::{ProviderBridge, ProviderRequest, ProviderResponse};
use std::sync::{Arc, Mutex};

pub struct MockProviderBridge {
  pub last_request: Arc<Mutex<Option<ProviderRequest>>>,
}

impl MockProviderBridge {
  pub fn new() -> Self {
    Self {
      last_request: Arc::new(Mutex::new(None)),
    }
  }
}

impl ProviderBridge for MockProviderBridge {
  fn call_provider(&self, request: ProviderRequest) -> ProviderResponse {
    *self.last_request.lock().expect("mock lock") = Some(request.clone());
    ProviderResponse {
      ok: true,
      payload_json: r#"{"mock":true}"#.into(),
      error_json: None,
    }
  }
}
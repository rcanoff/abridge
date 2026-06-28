use apple_bridge_core::{ProviderBridge, ProviderRequest, ProviderResponse};
use std::sync::{Arc, Mutex};

pub struct MockProviderBridge {
  pub last_request: Arc<Mutex<Option<ProviderRequest>>>,
  pub call_count: Arc<Mutex<usize>>,
}

impl MockProviderBridge {
  pub fn new() -> Self {
    Self {
      last_request: Arc::new(Mutex::new(None)),
      call_count: Arc::new(Mutex::new(0)),
    }
  }

  pub fn clone_for_server(&self) -> Self {
    Self {
      last_request: self.last_request.clone(),
      call_count: self.call_count.clone(),
    }
  }
}

impl ProviderBridge for MockProviderBridge {
  fn call_provider(&self, request: ProviderRequest) -> ProviderResponse {
    *self.call_count.lock().expect("mock lock") += 1;
    *self.last_request.lock().expect("mock lock") = Some(request.clone());
    ProviderResponse {
      ok: true,
      payload_json: r#"{"mock":true}"#.into(),
      error_json: None,
    }
  }
}

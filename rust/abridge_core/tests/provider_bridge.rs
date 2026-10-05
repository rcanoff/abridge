mod support;

use abridge_core::{ProviderBridge, ProviderRequest};
use support::mock_provider::MockProviderBridge;

#[test]
fn mock_provider_records_request() {
  let mock = MockProviderBridge::new();
  let response = mock.call_provider(ProviderRequest {
    provider: "eventkit".into(),
    operation: "list_calendars".into(),
    payload_json: "{}".into(),
  });

  assert!(response.ok);
  let recorded = mock.last_request.lock().expect("mock lock").clone().expect("request");
  assert_eq!(recorded.provider, "eventkit");
  assert_eq!(recorded.operation, "list_calendars");
}

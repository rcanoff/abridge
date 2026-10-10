mod support;

use abridge_core::{
  ProviderBridge, ProviderConfig, ProviderRequest, ProviderResponse, ServerConfig, create_server, start_server,
  stop_server,
};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant};
use support::port::{allocate_test_port, http_post_json};

const TEST_TOKEN: &str = "integration-test-token";
const LIST_LISTS_CALL: &str =
  r#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"eventkit_reminders_list_lists","arguments":{}}}"#;

#[derive(Default)]
struct Gate {
  open: bool,
  entered: usize,
}

/// Provider whose calls block until the test opens the gate, like a slow Apple framework call.
struct GatedProvider {
  gate: Arc<(Mutex<Gate>, Condvar)>,
}

impl ProviderBridge for GatedProvider {
  fn call_provider(&self, _request: ProviderRequest) -> ProviderResponse {
    let (lock, signal) = &*self.gate;
    let mut gate = lock.lock().expect("gate lock");
    gate.entered += 1;
    signal.notify_all();
    while !gate.open {
      gate = signal.wait(gate).expect("gate wait");
    }
    ProviderResponse {
      ok: true,
      payload_json: "{}".into(),
      error_json: None,
    }
  }
}

fn config_on_port(port: u16) -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port,
    bearer_token: TEST_TOKEN.into(),
    app_version: "test".into(),
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
    enabled_capabilities: vec!["eventkit.reminders.read".into()],
  }
}

/// `GET path` that gives up after `timeout` instead of hanging on a stalled server.
fn http_get_status_within(path: &str, port: u16, timeout: Duration) -> Option<u16> {
  let addr: SocketAddr = format!("127.0.0.1:{port}").parse().expect("socket addr");
  let mut stream = TcpStream::connect_timeout(&addr, timeout).ok()?;
  stream.set_read_timeout(Some(timeout)).ok()?;
  let request = format!("GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nConnection: close\r\n\r\n");
  stream.write_all(request.as_bytes()).ok()?;
  let mut response = String::new();
  stream.read_to_string(&mut response).ok()?;
  response.split_whitespace().nth(1)?.parse().ok()
}

fn wait_for_entered(gate: &(Mutex<Gate>, Condvar), at_least: usize, timeout: Duration) {
  let (lock, signal) = gate;
  let deadline = Instant::now() + timeout;
  let mut state = lock.lock().expect("gate lock");
  while state.entered < at_least {
    let remaining = deadline.saturating_duration_since(Instant::now());
    if remaining.is_zero() {
      return;
    }
    state = signal.wait_timeout(state, remaining).expect("gate wait").0;
  }
}

#[test]
fn slow_provider_calls_leave_the_server_responsive() {
  let port = allocate_test_port();
  let gate = Arc::new((Mutex::new(Gate::default()), Condvar::new()));
  let handle =
    create_server(config_on_port(port), Box::new(GatedProvider { gate: gate.clone() })).expect("create_server");
  start_server(handle.clone()).expect("start");

  // More concurrent blocked calls than the runtime has worker threads.
  let blocked_calls = thread::available_parallelism().map_or(4, usize::from) + 2;
  let callers: Vec<_> = (0..blocked_calls)
    .map(|_| thread::spawn(move || http_post_json("/mcp", "127.0.0.1", port, LIST_LISTS_CALL, TEST_TOKEN)))
    .collect();
  wait_for_entered(&gate, blocked_calls, Duration::from_secs(3));

  let health_status = http_get_status_within("/health", port, Duration::from_secs(3));

  let (lock, signal) = &*gate;
  lock.lock().expect("gate lock").open = true;
  signal.notify_all();
  let call_statuses: Vec<u16> = callers
    .into_iter()
    .map(|caller| caller.join().expect("caller").0)
    .collect();
  let entered = lock.lock().expect("gate lock").entered;
  stop_server(handle).expect("stop");

  assert_eq!(
    health_status,
    Some(200),
    "/health stalled while provider calls were blocked"
  );
  assert_eq!(
    entered, blocked_calls,
    "every call should reach the provider concurrently"
  );
  assert!(call_statuses.iter().all(|status| *status == 200), "{call_statuses:?}");
}

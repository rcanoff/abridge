#![allow(dead_code)]

use std::io::{Read, Write};
use std::net::TcpListener;
use std::net::TcpStream;
use std::sync::atomic::{AtomicU16, Ordering};

static NEXT_TEST_PORT: AtomicU16 = AtomicU16::new(45_000);

pub struct ReservedPort {
  _listener: TcpListener,
  pub port: u16,
}

pub fn reserve_port() -> ReservedPort {
  let listener = TcpListener::bind("127.0.0.1:0").expect("reserve port");
  let port = listener.local_addr().expect("local addr").port();
  ReservedPort {
    _listener: listener,
    port,
  }
}

/// Allocates a port verified free on `host` at selection time; retries on collision.
pub fn allocate_test_port_for(host: &str) -> u16 {
  for _ in 0..100 {
    let port = NEXT_TEST_PORT.fetch_add(1, Ordering::Relaxed);
    let candidate = if port < 60_000 { port } else { port % 15_000 + 45_000 };
    if TcpListener::bind((host, candidate)).is_ok() {
      return candidate;
    }
  }
  panic!("could not allocate test port for {host}");
}

/// Allocates a port verified free on IPv4 loopback at selection time.
pub fn allocate_test_port() -> u16 {
  allocate_test_port_for("127.0.0.1")
}

fn connect_addr(host: &str, port: u16) -> String {
  if host.contains(':') {
    format!("[{host}]:{port}")
  } else {
    format!("{host}:{port}")
  }
}

pub fn http_get(path: &str, host: &str, port: u16) -> (u16, String) {
  let mut stream = TcpStream::connect(connect_addr(host, port)).expect("tcp connect");
  let request = format!("GET {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n");
  stream.write_all(request.as_bytes()).expect("write request");
  let mut response = String::new();
  stream.read_to_string(&mut response).expect("read response");
  let status_line = response.lines().next().unwrap_or("");
  let status_code = status_line
    .split_whitespace()
    .nth(1)
    .unwrap_or("0")
    .parse()
    .unwrap_or(0);
  (status_code, response)
}

pub fn http_get_body(path: &str, host: &str, port: u16) -> (u16, String) {
  let (status_code, response) = http_get(path, host, port);
  let body = response.split("\r\n\r\n").nth(1).unwrap_or("").trim().to_string();
  (status_code, body)
}

pub fn health_body_ok(body: &str) -> bool {
  let trimmed = body.trim();
  trimmed == r#"{"ok":true}"# || trimmed == r#"{"ok": true}"#
}

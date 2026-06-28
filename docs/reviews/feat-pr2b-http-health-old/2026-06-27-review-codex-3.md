The new HTTP server lifecycle code breaks supported IPv6 loopback startup and introduces a concurrency race in `start()` that can desynchronize reported state from the actual bound listener. Those are correctness issues in the new functionality.

Full review comments:

- [P1] Bracket IPv6 loopback addresses before calling `TcpListener::bind` — /Users/rcanoff/Projects/apple-bridge/rust/apple_bridge_core/src/server.rs:209-209
  `ServerConfig` still accepts `"::1"` as a valid loopback host, but this code now builds the bind address with `format!("{}:{}", host, port)`, which produces strings like `::1:3020`. `tokio::net::TcpListener::bind` expects IPv6 literals in `[addr]:port` form, so every IPv6 loopback start will fail with `BindFailed` even though the configuration validator and new tests treat `::1` as supported.

- [P2] Keep `start()` atomic across concurrent callers — /Users/rcanoff/Projects/apple-bridge/rust/apple_bridge_core/src/server.rs:200-214
  `start()` checks `status.running`, drops the mutex, then does the actual bind and only later stores `runtime`/`shutdown_tx`/`server_task`. If two Swift tasks call `start()` at the same time, one can successfully bind while the other races into the error path and overwrites `status` to `stopped_with_error`, leaving `server_status()` false even though the first listener is still serving on the port. Because `ServerHandle` is `Arc`-backed and exported over UniFFI, this race is reachable from concurrent client calls.

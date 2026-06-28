Reviewing the uncommitted HTTP health changes. Loading required skills and reading the implementation files.
# Code Review — feat/pr2b-http-health

**Branch:** `feat/pr2b-http-health`  
**Base:** `main`  
**Date:** 2026-06-27  
**Scope:** No committed diff (HEAD == merge base). Review covers **uncommitted WIP** only.

---

## Findings

### 1. Concurrent `start()` / `stop()` has a TOCTOU race

**File:** `rust/apple_bridge_core/src/server.rs` (~lines 199–234, 237–252)  
**(rust-best-practices)**

`start()` releases the mutex after the `running` check, then does blocking I/O (`build_runtime`, `block_on(start_http_server)`) before re-locking to commit state. `stop()` can interleave in that window.

**Scenario A — stop during start:** `stop()` sees no runtime parts yet, becomes a no-op, sets `initial_status`. `start()` then commits `running=true` with a live listener — status says stopped while the server is running.

**Scenario B — concurrent starts:** Two threads can both pass `running == false`. The loser’s bind-failure path unconditionally writes `stopped_status_with_error`, which can overwrite the winner’s running status if timing aligns badly.

The mutex is meant to guard lifecycle state, but the critical section does not cover bind + task spawn. For a `Send + Sync` UniFFI object reachable from multiple threads, this is a correctness bug.

---

### 2. Bind-failure path ignores current running state

**File:** `rust/apple_bridge_core/src/server.rs` (~lines 216–222)  
**(rust-best-practices)**

On bind failure:

```rust
inner.status = stopped_status_with_error(&inner.config, error.to_string());
```

This runs without checking whether another concurrent `start()` already succeeded. A failed bind can clear `running` and set `last_error` while the HTTP server is actually listening — diagnostics and Swift UI would show the wrong state.

The server-task error handler (lines 152–157) correctly gates on `guard.status.running`; the `start()` error path should follow the same pattern.

---

### 3. `run_shutdown` silently no-ops when `shutdown_tx` is already cleared

**File:** `rust/apple_bridge_core/src/server.rs` (~lines 114–131, 150–157)  
**(rust-best-practices)**

`run_shutdown` requires all three of `runtime`, `shutdown_tx`, and `server_task` to be `Some`. After a spontaneous server exit, the error handler clears `shutdown_tx` and `server_task` but leaves `runtime`. A subsequent `stop()` skips graceful shutdown entirely.

This is mostly harmless if the task already finished, but `runtime` may linger until the next `clear_stale_runtime`. Holding the lock through the full shutdown sequence (or clearing `runtime` in the error handler) would make lifecycle state easier to reason about.

---

### 4. Redundant `serde_json` dev-dependency

**File:** `rust/apple_bridge_core/Cargo.toml` (lines 29–30)  
**(rust-best-practices)**

`serde_json` is already a production dependency (line 18). The `[dev-dependencies]` entry is redundant. Not a functional issue, but adds noise to the manifest.

---

### 5. `free_port()` does not hold the reservation through `start()`

**File:** `rust/apple_bridge_core/tests/support/port.rs` (lines 7–13)  
**(rust-best-practices)**

`free_port()` binds `127.0.0.1:0`, reads the port, then drops the listener. Between that drop and `start_server()`, a parallel test process (Cargo runs integration test binaries concurrently) or OS reuse could grab the same port. Low probability, but a classic source of flaky CI. Consider holding the listener until the server binds, or retry on `BindFailed`.

---

### 6. IPv6 bind address formatting is fragile

**File:** `rust/apple_bridge_core/src/server.rs` (line 209)  
**(rust-best-practices)**

`format!("{}:{}", host, port)` produces `::1:3020` for IPv6 loopback. The test helper correctly brackets IPv6 (`[::1]:port`), but the server does not. The `health_on_ipv6_loopback` test passes on macOS today, but unbracketed IPv6 literals are ambiguous per RFC 5952 and may fail on other platforms or parsers. Prefer bracketing when `host` contains `:`.

---

### 7. Positive notes (no issues)

- `/health` response `{"ok": true}` matches `docs/architecture-bootstrap-guide.md`.
- Loopback-only binding is enforced in `validate_config` before listen.
- Graceful shutdown via `oneshot` + `with_graceful_shutdown` follows architecture guidance.
- New `CoreError` variants (`BindFailed`, `RuntimeFailed`) follow `thiserror` + UniFFI conventions.
- `stop_releases_port_for_rebind` and `bind_failure_when_port_in_use` cover important lifecycle edges.
- Dependencies (`axum`, `tokio`, `serde_json`) match `docs/conventions.md`.

### 8. Out of scope (tooling/docs in diff)

Changes to `AGENTS.md`, `justfile`, and `local/review/**` are review-tooling, not HTTP health feature code. No correctness issues flagged in the Rust surface.

---

## Summary

Highest-risk items:

1. **Lifecycle TOCTOU race** — concurrent or interleaved `start()`/`stop()` can leave a running server with `running: false`, or corrupt status after a failed bind.
2. **Unconditional error status on bind failure** — can overwrite a successful concurrent start’s status.
3. **IPv6 address formatting** — may break off macOS despite current tests passing.
4. **Test port reservation** — `free_port()` pattern may cause rare flakes under parallel test execution.

---

## Verification Note

Ran locally:

- `just lint-rust` — passed (clippy, `-D warnings`)
- `just test-rust` — passed (21 tests, including 4 new `http_health` tests)

Not verified:

- Concurrent stress tests for `start()`/`stop()` interleaving (no such tests exist)
- Manual `curl http://127.0.0.1:<port>/health` smoke (tests use raw TCP instead)
- Swift FFI integration / `@concurrent` wrapping (no Swift call sites yet)
- `just build-rust` / UniFFI binding regeneration after error enum changes

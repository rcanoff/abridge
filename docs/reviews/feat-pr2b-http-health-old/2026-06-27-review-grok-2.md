I'll read the required skills and the changed source files to produce a thorough review.
# Code Review — feat/pr2b-http-health

**Branch:** `feat/pr2b-http-health`  
**Base:** `main`  
**Date:** 2026-06-27  
**Scope note:** Committed diff vs `main` is empty; all HTTP health work is in the uncommitted working tree. Findings below apply to that WIP unless noted.

---

## Findings

### 1. HTTP task exit leaves stale `running` state

**File:** `rust/apple_bridge_core/src/server.rs` (lines 82–91, 141–142)

When `axum::serve` returns an error, the spawned task only logs and exits. `ServerInner.status` remains `running: true` and `last_error: None`, so `status()` reports a healthy running server after the listener has died.

```82:91:rust/apple_bridge_core/src/server.rs
  let task = tokio::spawn(async move {
    let result = axum::serve(listener, router)
      .with_graceful_shutdown(async {
        let _ = shutdown_rx.await;
      })
      .await;
    if let Err(error) = result {
      tracing::error!(%error, "http server exited with error");
    }
  });
```

**Why it matters:** Swift/UI and future `/status` consumers can show “running” while `/health` and MCP are unreachable. Recovery requires an explicit `stop()`; `start()` will return `AlreadyRunning` on a dead server. Architecture expects operational status to reflect runtime errors (`last_error` in `ServerStatus`).

**Fix:** On task exit (error or unexpected completion), clear `running_server`, set `running: false`, and populate `last_error` (e.g. via a `watch` channel or `Arc<ServerInner>` handle passed into the task).

**(rust-best-practices)**

---

### 2. `block_on` while holding `Mutex` blocks all FFI entry points

**File:** `rust/apple_bridge_core/src/server.rs` (lines 127–139, 146–153)

`start()` and `stop()` acquire `inner` and then call `runtime.block_on(...)` before releasing the lock. Any concurrent `status()`, second `stop()`, or other FFI call blocks until bind/shutdown completes.

```127:139:rust/apple_bridge_core/src/server.rs
  pub fn start(&self) -> Result<(), CoreError> {
    let mut inner = self
      .inner
      .lock()
      .map_err(|_| CoreError::StateUnavailable)?;

    if inner.status.running {
      return Err(CoreError::AlreadyRunning);
    }

    let addr = format!("{}:{}", inner.config.host, inner.config.port);
    let router = http::router();
    let running = inner.runtime.block_on(start_http_server(&addr, router))?;
```

**Why it matters:** Architecture states `status()` must be safe across lifecycle phases. Holding the mutex across async I/O blocks every other method for the duration of start/stop. If a future HTTP handler re-enters `ServerHandle` on the same thread while the lock is held, this deadlocks (`std::sync::Mutex` is not re-entrant). `rust/AGENTS.md` warns against holding locks across async/callback boundaries.

**Fix:** Bind/shutdown under `block_on` without holding `inner`, then lock briefly to update `running_server` and `status`.

**(rust-best-practices)**

---

### 3. `Drop` uses `block_on` — tokio re-entrancy risk

**File:** `rust/apple_bridge_core/src/server.rs` (lines 119–123, 146–153)

```119:123:rust/apple_bridge_core/src/server.rs
impl Drop for ServerHandle {
  fn drop(&mut self) {
    let _ = self.stop();
  }
}
```

`stop()` calls `block_on` on the embedded runtime. If the last `Arc<ServerHandle>` is dropped on a worker thread of that same runtime (e.g. a future holding a clone), Tokio can deadlock or panic (“Cannot start a runtime from within a runtime”).

**Why it matters:** Today Swift likely holds the handle on the main thread, so this may not reproduce. As MCP handlers and shared handles are added, implicit cleanup via `Drop` becomes hazardous. Architecture prefers explicit shutdown signaling; `Drop` as a safety net should not assume a non-runtime thread.

**Fix:** Document that `stop()` must run off runtime worker threads before drop, or use a shutdown path that does not `block_on` from `Drop` (e.g. `shutdown_tx.send` without awaiting, runtime dropped after).

**(rust-best-practices)**

---

### 4. `build_runtime()` maps all failures to `StateUnavailable`

**File:** `rust/apple_bridge_core/src/server.rs` (lines 70–75)

```70:75:rust/apple_bridge_core/src/server.rs
fn build_runtime() -> Result<tokio::runtime::Runtime, CoreError> {
  tokio::runtime::Builder::new_multi_thread()
    .enable_all()
    .build()
    .map_err(|_| CoreError::StateUnavailable)
}
```

**Why it matters:** Runtime build failure is distinct from poisoned mutex / unavailable state. Callers and tests cannot distinguish “runtime failed to start” from other `StateUnavailable` paths. `rust/AGENTS.md` requires typed `CoreError` variants for recoverable boundary failures.

**Fix:** Add a dedicated variant (e.g. `RuntimeFailed { message: String }`) or reuse an existing construction-failure variant with the builder error string.

**(rust-best-practices)**

---

### 5. Tokio runtime allocated at `create_server`, not `start`

**File:** `rust/apple_bridge_core/src/server.rs` (lines 101–116)

A multi-thread Tokio runtime is created for every `ServerHandle`, even if `start()` is never called.

**Why it matters:** Extra threads and memory per handle. Architecture separates “construct state” from “bind and serve”; eager runtime creation couples them. Low risk for V1 (single server), but worth aligning with the documented lifecycle.

**Fix:** Create the runtime inside `start()` (or lazily on first start) and tear it down in `stop()`/drop.

**(rust-best-practices)**

---

### 6. Health test asserts substring, not structured JSON

**File:** `rust/apple_bridge_core/tests/http_health.rs` (lines 27–29)

```27:29:rust/apple_bridge_core/tests/http_health.rs
  let (status_code, response) = http_get("/health", "127.0.0.1", port);
  assert_eq!(status_code, 200);
  assert!(response.contains(r#""ok":true"#) || response.contains(r#""ok": true"#));
```

**Why it matters:** Architecture specifies minimal response `{"ok":true}`. Substring matching passes malformed bodies (e.g. `{"ok":true,"extra":...}` or HTML error pages containing that text). Weak contract for the primary HTTP smoke test.

**Fix:** Parse the response body as JSON and assert `ok == true` (and optionally `Content-Type: application/json`).

**(rust-best-practices)**

---

### 7. Missing trailing newlines at EOF

**Files:** `rust/apple_bridge_core/src/error.rs`, `tests/error_display.rs`, `tests/support/mod.rs`, `tests/http_health.rs`, `tests/support/port.rs`

Several touched files end without a final newline.

**Why it matters:** Minor style/consistency issue; some tooling and reviewers flag it on every diff hunk.

**(rust-best-practices)**

---

### 8. Uncommitted non-feature files (informational)

**Files:** `justfile` (`@` prefix), `local/review/**`

These are unrelated to PR 2b HTTP health. The `justfile` change is benign (suppress echo). No correctness/concurrency findings for the Rust server from this tooling.

**(requesting-code-review)**

---

## Summary

Highest-risk items:

1. **Silent HTTP server death leaves `status.running == true`** — incorrect operational state until manual `stop()`.
2. **Mutex held across `block_on` in `start()`/`stop()`** — blocks FFI and risks deadlock on re-entrant calls.
3. **`Drop` → `block_on`** — latent Tokio deadlock if handle is released from a runtime worker thread.
4. **Misleading `StateUnavailable` for runtime build failure** — weak error semantics at the FFI boundary.
5. **Health integration test is loosely specified** — may not catch regressions in response shape.

---

## Verification Note

**Ran successfully:**

- `just lint-rust` — clippy clean (`-D warnings`)
- `just test-rust` — 19 tests passed (including `http_health`, `server_lifecycle`, `bind_failed_display`)

**Not verified:**

- Manual `curl http://127.0.0.1:<port>/health` smoke (recommended in AGENTS.md for MCP/HTTP changes)
- UniFFI Swift rebuild after `BindFailed` enum addition (`just build-rust` + Swift tests)
- Behavior under simulated `axum::serve` failure (no test covers stale-running scenario)
- IPv6 `::1` bind path (config accepts it; no integration test exercises bind with `host = "::1"`)

**Committed branch state:** No commits ahead of `main` for this feature; review reflects uncommitted WIP only.

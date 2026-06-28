I'll load the required skills and read the changed files to review correctness, concurrency, and conventions.
I have the full picture: many earlier review issues are fixed (phase machine, generation counter, IPv6 bracketing, bind-failure status). Writing the review against the current uncommitted code.
# Code Review — feat/pr2b-http-health

**Branch:** `feat/pr2b-http-health`  
**Base:** `main`  
**Date:** 2026-06-27  
**Scope:** Committed diff vs `main` is empty (HEAD == merge base). All findings apply to the **uncommitted WIP** implementing HTTP bind, `/health`, and graceful shutdown.

---

## Findings

### 1. `start()` returns `Ok(())` when a concurrent `stop()` cancels startup

**File:** `rust/apple_bridge_core/src/server.rs` (lines 286–295)  
**(rust-best-practices)**

When `start()` successfully binds but loses the generation race (e.g. another thread called `stop()` while phase was `Starting`), it aborts the listener and returns `Ok(())`:

```286:295:rust/apple_bridge_core/src/server.rs
    drop(inner);
    abort_started_server(runtime, shutdown_tx, server_task);

    let mut inner = self
      .inner
      .lock()
      .map_err(|_| CoreError::StateUnavailable)?;
    inner.phase = ServerPhase::Stopped;
    inner.status = initial_status(&inner.config);
    Ok(())
```

**Why it matters:** The caller invoked `start()` and receives success with no error variant, but `status()` shows `running: false`. Swift/UniFFI consumers that only check the `Result` (and not `server_status()`) can treat a failed start as success. For a `Send + Sync` handle reachable from multiple threads, this is an ambiguous API contract.

---

### 2. `stop()` during `Starting` can leave a brief ghost listener

**File:** `rust/apple_bridge_core/src/server.rs` (lines 306–310, 287)  
**(rust-best-practices)**

`stop()` in the `Starting` branch bumps `start_generation`, sets phase to `Stopped`, updates status, and returns immediately — it does not wait for the in-flight `block_on(start_http_server(...))` to finish or for `abort_started_server` to run:

```306:310:rust/apple_bridge_core/src/server.rs
        ServerPhase::Starting => {
          inner.start_generation += 1;
          inner.phase = ServerPhase::Stopped;
          inner.status = initial_status(&inner.config);
          return Ok(());
```

**Why it matters:** If `block_on` has already bound the port but not yet committed state, there is a window where `status()` reports stopped while the HTTP server is still accepting connections on localhost. The generation/abort path eventually cleans up, but diagnostics and any code assuming “stopped means not listening” are briefly wrong. A quick start→stop toggle from Swift could hit this.

---

### 3. Tokio `Runtime` retained after unexpected server exit

**File:** `rust/apple_bridge_core/src/server.rs` (lines 172–181, 305)  
**(rust-best-practices)**

When `axum::serve` fails, the spawned task clears `shutdown_tx` and `server_task` and sets phase to `Stopped`, but leaves `inner.runtime` populated:

```172:180:rust/apple_bridge_core/src/server.rs
    if let Err(error) = result {
      tracing::error!(%error, "http server exited with error");
      if let Ok(mut guard) = task_inner.lock() {
        if guard.phase == ServerPhase::Running {
          guard.phase = ServerPhase::Stopped;
          guard.status = stopped_status_with_error(&guard.config, error.to_string());
          guard.shutdown_tx = None;
          guard.server_task = None;
        }
```

A subsequent `stop()` on `Stopped` returns immediately without dropping the runtime:

```305:305:rust/apple_bridge_core/src/server.rs
        ServerPhase::Stopped => return Ok(()),
```

**Why it matters:** After a spontaneous server exit, a thread pool and runtime linger until the next `start()` (`clear_stale_runtime`) or `Drop`. Status correctly reflects the failure, but resources are held longer than necessary and `stop()` does not fully tear down a crashed server.

---

### 4. No test for unexpected server-task exit updating status

**File:** `rust/apple_bridge_core/tests/http_health.rs`  
**(rust-best-practices)**

The serve-error handler (finding 3) and bind-failure status recording are important lifecycle behaviors called out in `rust/AGENTS.md` (“graceful shutdown, task cancellation where applicable”). `bind_failure_when_port_in_use` covers bind errors, but there is no test asserting that when the accept loop dies, `status()` transitions to `running: false` with `last_error` set and a subsequent `start()` succeeds.

**Why it matters:** This was a gap in earlier reviews; the code now handles it, but without a test the regression path is unguarded. Simulating serve failure is awkward, yet even a focused unit/integration seam test would lock the contract.

---

### 5. `ephemeral_port()` releases reservation before server bind

**File:** `rust/apple_bridge_core/tests/support/port.rs` (lines 21–24)  
**(rust-best-practices)**

```21:24:rust/apple_bridge_core/tests/support/port.rs
/// Returns a port from the OS, releasing the reservation immediately before bind.
pub fn ephemeral_port() -> u16 {
  reserve_port().port
}
```

**Why it matters:** Cargo runs integration test binaries (`http_health`, `server_lifecycle`, etc.) in parallel. Two binaries can draw the same ephemeral port in the gap between listener drop and `start_server()` bind, causing rare `BindFailed` flakes. `reserve_port()` exists for the bind-failure test; lifecycle/health tests use the weaker helper.

---

### 6. `Drop` skips shutdown when the mutex is poisoned

**File:** `rust/apple_bridge_core/src/server.rs` (lines 218–223)  
**(rust-best-practices)**

```218:223:rust/apple_bridge_core/src/server.rs
    let parts = match self.inner.lock() {
      Ok(mut inner) => {
        inner.phase = ServerPhase::Stopped;
        take_shutdown_parts(&mut inner)
      }
      Err(_) => return,
    };
```

**Why it matters:** A panic while holding `inner` (e.g. in future callback code) poisons the mutex; `Drop` then returns without running `run_shutdown`, potentially leaking a bound listener and Tokio runtime until process exit. Unlikely today, but on a UniFFI path where panics abort the host app, incomplete cleanup worsens the failure mode.

---

### 7. Positive notes (no issues)

- `/health` handler and `{"ok": true}` response match `docs/architecture-bootstrap-guide.md` and PR 2b spec.
- Loopback-only binding enforced in `validate_config` before listen.
- `ServerPhase` + `start_generation` address the TOCTOU races flagged in earlier reviews (bind-failure status is generation-gated; concurrent `start()` blocked during `Starting`).
- IPv6 bind addresses use `bind_address()` bracketing; `health_on_ipv6_loopback` covers `::1`.
- Graceful shutdown via `oneshot` + `with_graceful_shutdown`; `run_shutdown` offloads `block_on` to a helper thread to avoid nested-runtime panics.
- New `CoreError` variants follow `thiserror` + UniFFI conventions; display tests present.
- Dependencies match `docs/conventions.md`; no Swift changes (correct for PR 2b scope).

### 8. Out of scope (tooling/docs in diff)

Changes to `AGENTS.md`, `justfile`, and `local/review/**` are review/agent tooling, not HTTP health feature code. No correctness findings there.

---

## Summary

1. **`start()` silent success on race-cancelled startup** — FFI callers can miss that the server never reached `Running`.
2. **Ghost listener window on `stop()` during `Starting`** — status says stopped while the port may still be bound briefly.
3. **Runtime retained after spontaneous server exit** — `stop()` on a crashed server does not release the Tokio runtime.
4. **Missing test for serve-failure status transition** — fixed in code, unguarded in tests.
5. **`ephemeral_port()` TOCTOU** — parallel test binaries may flake on port collision.

---

## Verification Note

Ran locally:

- `just lint-rust` — passed (clippy, `-D warnings`)
- `just test-rust` — passed (21 tests, including 4 new `http_health` tests)

Not verified:

- Concurrent/interleaved `start()`/`stop()` stress (no such tests)
- Manual `curl http://127.0.0.1:<port>/health` smoke (tests use raw TCP)
- `just build-rust` / UniFFI binding regeneration after new `CoreError` variants
- Swift `@concurrent` wrapping of blocking `start()`/`stop()` (no Swift changes in this diff)

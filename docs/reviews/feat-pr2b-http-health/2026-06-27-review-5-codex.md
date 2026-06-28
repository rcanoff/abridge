# Review: `feat/pr2b-http-health` vs `main`  
Date: 2026-06-27

## Findings

### Important: orphaned Tokio runtime after an unexpected server-task failure `(rust-best-practices)`
- File: `rust/apple_bridge_core/src/server.rs` (`start_http_server` error path; `stop` early return on `ServerPhase::Stopped`)
- Evidence: in the spawned server task, the error branch sets `guard.phase = ServerPhase::Stopped`, `guard.shutdown_tx = None`, and `guard.server_task = None`, but it does not clear `guard.runtime`. Later, `stop()` returns immediately for `ServerPhase::Stopped`, so that stale runtime is never torn down unless a later `start()` or `drop` happens.
- Why it matters: if `axum::serve(...)` exits with an error after a successful start, the handle reports a stopped server while still retaining a live Tokio runtime and its worker threads. That leaks resources and leaves cleanup dependent on a later restart/drop rather than the failure path itself.
- Fix: clear or shut down `runtime` in the server-task failure path, or make `stop()` clean stale runtime state even when the phase is already `Stopped`.

### Minor: lifecycle tests rely on fixed sleeps and can flake under scheduler variance `(rust-best-practices)`
- File: `rust/apple_bridge_core/tests/server_lifecycle.rs` (`stop_during_start_releases_port_before_return`, `concurrent_start_rejected_while_stop_awaits_start_completion`)
- Evidence: both tests use `thread::sleep(Duration::from_millis(5));` to try to force an interleaving before calling `stop_server(...)`.
- Why it matters: these tests are timing-sensitive rather than state-synchronized. On a loaded CI machine or with different thread scheduling, the 5 ms window may be too short or unnecessary, producing nondeterministic results.
- Fix: replace the sleep with an explicit synchronization point so the test knows when `start_server` has reached the intended phase before racing `stop_server`.

## Summary
1. `server.rs` can retain a live Tokio runtime after an unexpected HTTP server failure, because the stopped-state cleanup path does not release it.
2. The new concurrency lifecycle tests depend on `sleep(5 ms)` and are prone to CI flakiness.

## Verification Note
Assessed only from the provided diff, inventory, existing context, and inlined skills. I could review control flow, state transitions, and test design, but I could not confirm runtime behavior, actual flake rate, or whether surrounding code outside the prompt mitigates these issues.
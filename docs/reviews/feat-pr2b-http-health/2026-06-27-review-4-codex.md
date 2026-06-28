# Review — `feat/pr2b-http-health` vs `main` — 2026-06-27

## Findings

### Important: `stop()` opens a race that lets a second `start()` clobber server state `(rust-best-practices)`
- File: `rust/apple_bridge_core/src/server.rs` (`stop()` branch for `ServerPhase::Starting`, around the block that sets `inner.phase = ServerPhase::Stopped`; `start()` cancellation path after `abort_started_server(...)`)
- What’s wrong: when `stop()` is called during `Starting`, it immediately sets `phase` to `Stopped` before the first `start()` finishes unwinding. A concurrent second `start()` can then pass the `phase` check and begin its own startup. If the first `start()` later notices the generation mismatch, it unconditionally executes:
  - `inner.phase = ServerPhase::Stopped;`
  - `inner.status = initial_status(&inner.config);`
- Why it matters: that stale cleanup can overwrite the newer startup’s state, causing the fresh start to be cancelled or leaving `server_status()` reporting stopped while a newer startup is in flight. This is a real lifecycle correctness bug in the branch’s new concurrency model.
- Fix: keep `Starting` visible until the in-flight start has fully completed or cancelled, or gate `start()` on `start_in_progress` as well as `phase`. The cancelled-start cleanup also needs to verify it is still operating on the active generation before resetting shared state.

## Summary

1. The new start/stop lifecycle has a concurrency hole: a `stop()` during startup can admit a second `start()`, and the first startup’s stale cleanup can then corrupt the newer attempt’s state.

## Verification Note

Assessed only from the provided diff, diff inventory, existing code context, and inlined skills. I could review the lifecycle/state-machine logic, HTTP route shape, and test coverage added here; not visible in diff, so I could not confirm end-to-end UniFFI/Swift integration behavior or CI/runtime scheduling characteristics beyond the code shown.
# Review: `feat/pr2b-http-health` against `main` on 2026-06-27

## Findings

### Important: `stop()` can return before a concurrent `start()` has actually finished unwinding `(rust-best-practices)`
- **Reference:** `rust/apple_bridge_core/src/server.rs` in `stop()`, the `ServerPhase::Starting` arm sets `inner.start_generation += 1`, flips `inner.phase = ServerPhase::Stopped`, resets status, and returns `Ok(())` immediately; `start()` only notices cancellation later in its post-bind generation check and then calls `abort_started_server(...)`.
- **What’s wrong:** The public lifecycle contract says the server is stopped once `stop()` returns, but in this path the in-flight `start()` may still be creating the runtime, binding the socket, and only then shutting itself back down.
- **Why it matters:** Callers can observe a false stopped state and immediately try to rebind or restart, producing racy behavior around the same port. The added test `stop_during_start_leaves_consistent_status` only checks final status, not that `stop()` is synchronous with resource release.
- **Fix:** Make the `Starting` path wait for the in-flight start to fully resolve before returning, or otherwise expose/start a lifecycle state that does not report a completed stop until the bind/runtime cleanup has actually finished.

## Summary

1. `stop()` is not fully synchronous when racing with `start()`, so API callers can get `Ok(())` before startup resources are actually released.

## Verification Note

Assessed only from the provided diff, diff inventory, existing code context, and inlined skills. I could evaluate the lifecycle race above from the code path shown; I could not confirm runtime behavior beyond what is visible in the diff.
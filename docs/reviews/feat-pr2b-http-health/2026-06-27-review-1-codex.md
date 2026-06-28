# Review: `feat/pr2b-http-health` vs `main` (2026-06-27)

## Findings

### Important: `start()` can leave the server permanently stuck in `Starting` after runtime creation failure `(rust-best-practices)`

- **File:** `rust/apple_bridge_core/src/server.rs` — in `start()`, the hunk that sets `inner.phase = ServerPhase::Starting;` before `let runtime = build_runtime()?;`
- **What’s wrong:** `start()` mutates shared state to `Starting` and increments `start_generation` before attempting to build the Tokio runtime. If `build_runtime()` returns `Err(CoreError::RuntimeFailed { .. })`, the `?` exits early and never restores `phase` or `status`.
- **Why it matters:** After a runtime init failure, subsequent `start()` calls will hit `if inner.phase == ServerPhase::Running || inner.phase == ServerPhase::Starting { return Err(CoreError::AlreadyRunning); }`, even though no server is actually running. This is a real state-corruption bug in the failure path.
- **Fix:** Either build the runtime before flipping `phase` to `Starting`, or explicitly roll the state back to `Stopped` and set `last_error` when `build_runtime()` fails.

## Summary

1. `start()` has a broken error path: a runtime creation failure can strand the handle in `Starting` and block future restarts.

## Verification Note

Assessment is limited to the committed diff, the listed inventory, the provided unchanged `config.rs` context, and the inlined skills. I did not run tests, build the crate, inspect other files, or validate behavior outside what is visible here.
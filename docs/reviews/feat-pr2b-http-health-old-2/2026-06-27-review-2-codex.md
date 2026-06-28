# Review: `feat/pr2b-http-health` vs `main` (2026-06-27)

## Findings

### 1. Real socket binding ships without enforcing the localhost-only security boundary
- **File:** `rust/apple_bridge_core/src/server.rs` (`start`, `bind_address`, `start_http_server`)
- **What’s wrong:** This branch changes `start()` from a state flip into a real network bind using `inner.config.host` verbatim, but the diff adds no matching validation that restricts binds to `127.0.0.1`.
- **Why it matters:** The project rule is explicit that the bridge must stay localhost-only. With this code, a caller can bind `0.0.0.0` or another non-loopback interface and expose the MCP server off-host. That turns this PR into a security boundary regression, not just a health endpoint addition.
- **How to fix:** Reject non-loopback hosts during config validation before reaching `TcpListener::bind`, and add negative tests for non-localhost addresses. `(requesting-code-review)`

### 2. Runtime creation failure leaves the handle stuck in `Starting`
- **File:** `rust/apple_bridge_core/src/server.rs` (`start`)
- **What’s wrong:** `start()` sets `inner.phase = ServerPhase::Starting` and increments `start_generation` before calling `build_runtime()`. If `build_runtime()` returns `Err`, the method exits immediately and never restores `phase` or `status`.
- **Why it matters:** A transient runtime initialization failure permanently corrupts the handle’s lifecycle state. Subsequent `start()` / `stop()` calls can no longer reason about the server correctly, which is exactly the kind of state machine bug that is hard to recover from in production.
- **How to fix:** Either build the runtime before transitioning to `Starting`, or roll back `phase` and `status` on the `build_runtime()` error path. `(rust-best-practices)`

### 3. The new start/stop race test is timing-based and will be flaky in CI
- **File:** `rust/apple_bridge_core/tests/server_lifecycle.rs` (`stop_during_start_leaves_consistent_status`)
- **What’s wrong:** The test tries to hit a concurrency window by sleeping for 5 ms before calling `stop_server()`.
- **Why it matters:** Sleep-based race tests are nondeterministic: on a fast runner the race may never happen, and on a slow or loaded runner it may happen in a different phase. That makes the suite noisy and weakens confidence in the lifecycle logic this PR is introducing.
- **How to fix:** Synchronize the test with an explicit barrier/hook so `stop_server()` is issued at a known point in startup instead of relying on scheduler timing. `(rust-best-practices)`

### 4. The test port allocator does not actually reserve the port it returns
- **File:** `rust/apple_bridge_core/tests/support/port.rs` (`allocate_test_port`)
- **What’s wrong:** `allocate_test_port()` binds a candidate port only to check availability, then drops the listener and returns the number.
- **Why it matters:** Another test or process can claim that port before the server under test starts, creating intermittent bind failures unrelated to the behavior being tested. The new HTTP tests increase exposure to this kind of flake.
- **How to fix:** Keep the listener reserved until the server is ready to bind, or redesign the test seam so the OS chooses the port and the test reads back the bound address. `(rust-best-practices)`

## Summary

1. The branch introduces real network exposure without enforcing the repo’s localhost-only rule.
2. `start()` can leave `ServerHandle` in a permanently inconsistent lifecycle state if runtime creation fails.
3. The new lifecycle and port-selection tests are race-prone and likely to produce CI flakes.

## Verification Note

This review is based on the provided diffs and inlined skills only. I could assess lifecycle/state-machine logic, security boundary regressions, and test determinism from the code shown, but not runtime behavior, existing config validation outside the diff, or whether CI currently masks the new test flakiness.
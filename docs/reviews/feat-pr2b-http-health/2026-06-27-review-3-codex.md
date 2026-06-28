# Review: `feat/pr2b-http-health` vs `main` (2026-06-27)

## Finding 1
**File:** `rust/apple_bridge_core/src/server.rs:53-60`, `rust/apple_bridge_core/tests/server_lifecycle.rs:47-48`  
**Issue:** `(rust-best-practices)` `running_status()` now hard-codes every provider to `healthy: false` after a successful `start()`, and the lifecycle test was updated to lock that behavior in.  
**Why it matters:** Before this diff, enabled providers were reported healthy when the server was running. This change makes `ServerStatus` advertise a degraded provider state immediately after startup, which is a behavioral regression for any UI or diagnostics consumer reading provider health.

## Finding 2
**File:** `rust/apple_bridge_core/tests/support/port.rs:22-29`, `rust/apple_bridge_core/tests/http_health.rs:31-39`  
**Issue:** `(rust-best-practices)` `allocate_test_port()` only probes `127.0.0.1`, but `health_on_ipv6_loopback` reuses that port on `::1`.  
**Why it matters:** The IPv6 test can still collide with an existing listener on `::1`, so this new coverage is flaky and does not reliably prove IPv6 loopback binding works. The port allocator needs to reserve or validate the same address family the test binds.

## Finding 3
**File:** `rust/apple_bridge_core/src/server.rs:219-220`, `rust/apple_bridge_core/src/server.rs:254-265`  
**Issue:** `(rust-best-practices)` `build_runtime()?` can return `CoreError::RuntimeFailed` before `ServerInner.status.last_error` is updated, unlike the bind-failure path which persists the error into status.  
**Why it matters:** Callers that inspect `server_status()` after a failed start will get diagnostics for `BindFailed` but not for `RuntimeFailed`, which makes startup error reporting inconsistent and drops one failure class from observable state.

## Summary
1. Provider health reporting regressed: a running server now reports all providers unhealthy.
2. The IPv6 health test uses an IPv4-only port allocator, so the new coverage is flaky.
3. Runtime creation failures are returned but not persisted into `ServerStatus.last_error`.

## Verification Note
Assessment is based only on the provided diff, diff inventory, existing code context, and inlined skills. I did not run tests, builds, linters, shell commands, or inspect any files outside the prompt.
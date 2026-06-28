# Code review — `feat/pr2b-http-health`

**Base:** `main` (`7f2eac04`) → **HEAD:** `3257b11d`  
**Date:** 2026-06-27  
**Scope:** Committed diff vs `main` (working tree reported dirty; uncommitted diff not included)

### Strengths

- Clear lifecycle model with `ServerPhase`, `start_generation`, and abort-on-stale-start after async bind. (rust-best-practices)
- `/health` is minimal and test-backed (IPv4/IPv6, rebind after stop, bind failure). (test-driven-development)
- Typed errors (`BindFailed`, `RuntimeFailed`, `StartCancelled`) with display tests. (rust-best-practices)
- IPv6 listen/connect addressed via bracketed `bind_address`. (rust-best-practices)
- Graceful shutdown via oneshot + dedicated shutdown thread avoids blocking the UniFFI caller awkwardly. (rust-best-practices)
- HTTP serve failures update `last_error` and phase under the mutex. (rust-best-practices)

### Findings

#### Critical

*None identified from the diff alone.*

#### Important

1. **Concurrent `start()` while an earlier start is still binding** (requesting-code-review) (rust-best-practices)  
   - **Where:** `rust/apple_bridge_core/src/server.rs` — `stop()` `ServerPhase::Starting` branch; `start()` after lock is released for `block_on`  
   - **What:** `stop()` during `Starting` sets `phase` to `Stopped` and bumps `start_generation` but does not block a new `start()`. The in-flight `start()` still runs `runtime.block_on(start_http_server(...))` without holding the mutex. A second `start()` can begin binding the same host/port before the first finishes or aborts.  
   - **Why:** Two listeners or confusing errors (bind race, `StartCancelled` on the wrong caller) undermine the menu-bar start/stop contract.  
   - **Fix direction:** Treat “start in progress” as exclusive until bind completes or is aborted (e.g. keep a “starting” guard across the async gap, or reject `start()` while any start task is live).

2. **No test for stop-during-start / overlapping start** (test-driven-development)  
   - **Where:** `rust/apple_bridge_core/tests/http_health.rs` (visible tests only cover happy path, rebind, bind failure)  
   - **What:** The generation/abort logic is the hardest part of this PR; the diff does not show a test that calls `stop()` (or a second `start()`) while the first `start()` is inside `block_on`.  
   - **Why:** Regressions on finding #1 would not be caught in CI.  
   - **Fix:** Add an integration test that exercises stop-while-starting or parallel start and asserts a single bound listener and stable status/errors.

#### Minor

3. **Missing final newlines** (rust-best-practices)  
   - **Where:** `rust/apple_bridge_core/src/error.rs`, `http.rs`, `tests/error_display.rs` (`\ No newline at end of file` in diff)  
   - **What:** EOF newline omitted.  
   - **Why:** Noise in future diffs; many style checkers expect trailing newline.  
   - **Fix:** Add trailing newlines.

4. **`AGENTS.md` review-triage docs bundled with runtime PR** (requesting-code-review)  
   - **Where:** `AGENTS.md`  
   - **What:** Agent workflow documentation unrelated to HTTP health.  
   - **Why:** Reviewers must separate product risk from doc churn; not a blocker if intentional.  
   - **Fix:** Optional split commit or call out in PR description.

5. **Health JSON shape undocumented in code** (rust-best-practices)  
   - **Where:** `rust/apple_bridge_core/src/http.rs`  
   - **What:** `{"ok": true}` is only implied by tests (`health_body_ok`).  
   - **Why:** Swift/MCP clients may depend on a stable contract later.  
   - **Fix:** Brief module comment or shared test helper documenting the contract (version field can wait).

### Recommendations

- Document expected behavior when `stop()` is called during `Starting` (success vs `StartCancelled` on the in-flight `start()` caller) in PR notes or a short comment near `ServerPhase::Starting` handling.  
- Consider reusing one Tokio runtime across start/stop cycles later if startup cost matters (not required for this PR).

### Summary

1. Highest risk: `stop()` during `Starting` allows another `start()` while the first bind may still be in flight (port double-bind / ambiguous errors).  
2. Missing automated test for that concurrency window despite sophisticated generation logic.  
3. Minor hygiene: EOF newlines and optional doc/PR scope clarity.

### Verification note

Assessment is from the **committed diff and inlined review skills only**. Tests, `just lint-rust`, `just test-rust`, and manual `curl /health` were **not** run per review constraints. Truncated portions of `http_health.rs` (e.g. end of `bind_failure_when_port_in_use`) were not fully visible; bind-failure coverage is assumed complete from the test name and partial hunk. Uncommitted changes (e.g. `justfile`) were not reviewed.

### Assessment

**Ready to merge?** **With fixes**

**Reasoning:** The HTTP health endpoint, shutdown path, and error typing look solid and well tested for the happy path and bind failure, but the start/stop state machine likely permits overlapping starts during the async bind window unless guarded or tested otherwise. Address or explicitly disprove finding #1 and add the missing concurrency test before merge.

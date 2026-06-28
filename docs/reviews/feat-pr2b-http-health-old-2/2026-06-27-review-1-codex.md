# Review: `feat/pr2b-http-health` vs `main` on 2026-06-27

## Findings

### Important: server can report `running = true` after the Axum task has already died `(rust-best-practices)`
- File: `rust/apple_bridge_core/src/server.rs:129`, `rust/apple_bridge_core/src/server.rs:175`
- What's wrong: the background task only records a failure when `guard.phase == ServerPhase::Running`, but `start()` does not flip the phase to `Running` until after `start_http_server()` returns and the mutex is reacquired. If the spawned server task exits in that window, the failure path is skipped and `start()` can still publish a healthy running status while the task is already gone.
- Why it matters: this creates a false-positive server state and can leave callers believing `/health` is available when the listener has already failed.
- Fix: make task-exit handling cover the `Starting` phase as well, or set the phase/status before spawning and reconcile the final state after the task handle is stored.

### Important: the new port helper reintroduces TOCTOU flakiness into integration tests `(rust-best-practices)`
- File: `rust/apple_bridge_core/tests/support/port.rs:19`
- What's wrong: `ephemeral_port()` binds to port `0`, reads the assigned port, and immediately releases it before the server binds. The tests then reuse that freed port in `server_lifecycle.rs` and `http_health.rs`.
- Why it matters: another process can claim the port between release and bind, making these tests nondeterministic in CI and under parallel local runs.
- Fix: keep the reservation alive until the code under test has bound the listener, or let the server expose the actual bound port after binding to port `0`.

### Important: the review tool does not enforce the repo’s mandatory `using-superpowers` startup skill `(requesting-code-review)`
- File: `local/review/bin/review_lib.py:286`
- What's wrong: `resolve_skills()` hardcodes `always = ["requesting-code-review"]` and never includes `using-superpowers`, even though `local/review/skills.toml` declares it and the repo `AGENTS.md` says it must be invoked at the start of every conversation.
- Why it matters: generated review prompts can systematically miss required project instructions, so agent reviews may not follow the repo’s own review workflow contract.
- Fix: include `using-superpowers` in the always-loaded skill set before `requesting-code-review`.

## Summary

1. The committed branch diff is empty, so there are no committed-change findings for `feat/pr2b-http-health` itself.
2. The uncommitted Rust server changes have a startup race that can publish a stale healthy state after the server task has already exited.
3. The new test port helper makes HTTP/server lifecycle tests flaky by freeing the selected port before bind.
4. The local review tooling does not actually load the repo’s mandatory startup skill.

## Verification Note

This review is limited to the provided diff and inlined skills. I could assess control flow, state handling, and test determinism from the patch, but I could not confirm runtime behavior, UniFFI integration details, or whether any existing code outside the diff mitigates these issues.
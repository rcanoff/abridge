### Header

- **Branch:** `feat/pr2b-http-health`
- **Base:** `main`
- **Date:** 2026-06-27

### Strengths

- Loopback binding is enforced upstream via `validate_config` and `is_loopback_host` in existing `config.rs`, aligned with AGENTS localhost-only rule.
- `bind_address` brackets IPv6 literals (`host.contains(':')`) before `TcpListener::bind`, matching `health_on_ipv6_loopback` in the diff inventory.
- Typed errors for bind, runtime, and cancelled start with dedicated `error_display` tests.
- HTTP layer is thin: `http::router()` plus `/health` returning `{"ok": true}`.
- Graceful shutdown path (`oneshot`, `axum::serve().with_graceful_shutdown`, `run_shutdown` on a helper thread) fits calling `ServerHandle` from non-async UniFFI surfaces.
- Integration tests cover health JSON, IPv6 loopback, port reuse after stop, bind failure, and stop-during-start consistency.

### Findings

#### Important

1. **Provider `healthy` tied to `enabled`, not probe**
   - **File:** `rust/apple_bridge_core/src/server.rs` (`running_status`)
   - **Evidence:** `healthy: p.enabled` when building `provider_statuses` for running state.
   - **Issue:** Diagnostics imply providers are healthy whenever enabled, with no HTTP or bridge check in this PR.
   - **Why it matters:** Swift/UI or future MCP clients may treat `ServerStatus` as live health and mis-route traffic.
   - **Fix:** Keep `healthy: false` until real checks exist, or rename/document the field as “configured” not “healthy”.
   - **(rust-best-practices)**

2. **Serve failure only reconciles state for `Running` / `Starting`**
   - **File:** `rust/apple_bridge_core/src/server.rs` (`start_http_server` task, `if let Err(error) = result` block)
   - **Evidence:** `if matches!(guard.phase, ServerPhase::Running | ServerPhase::Starting)` before setting `Stopped` and `last_error`.
   - **Issue:** If the server task errors while phase is `Stopping` or another transition, inner state may not match a dead listener/task.
   - **Why it matters:** Rare races after `stop()` or cancelled start could leave stale `phase` / handles until the next `start()`.
   - **Fix:** Define behavior for all phases on unexpected exit (always clear task handles; set `last_error` when still logically “was running”).
   - **(rust-best-practices)** — full `start()` / `stop()` generation logic is **not visible in diff**; treat as hypothesis until that hunk is read.

#### Minor

1. **Missing newline at end of file**
   - **Files:** `rust/apple_bridge_core/src/error.rs`, `rust/apple_bridge_core/src/http.rs` (diff `\ No newline at end of file`)
   - **Issue:** Repo style typically expects trailing newline.
   - **Fix:** Add final newline.
   - **(rust-best-practices)**

2. **Shutdown join/send results discarded**
   - **File:** `rust/apple_bridge_core/src/server.rs` (`run_shutdown`: `let _ = shutdown_tx.send(())`, `let _ = server_task.await`, `let _ = join.join()`)
   - **Issue:** Panics or failed joins are silent aside from serve-path `tracing::error!`.
   - **Impact:** Harder to diagnose shutdown hangs in the field.
   - **Fix:** Log at `warn`/`error` when join fails or oneshot is closed.
   - **(rust-best-practices)**

3. **`Drop` resets status to `initial_status`**
   - **File:** `rust/apple_bridge_core/src/server.rs` (`impl Drop for ServerHandle`)
   - **Evidence:** After `run_shutdown`, `inner.status = initial_status(&inner.config)`.
   - **Issue:** `last_error` from a failed run may be cleared on handle drop without an explicit `stop()`.
   - **Impact:** FFI consumers may lose the last failure reason if the handle is dropped after error.
   - **Fix:** Preserve `last_error` on drop or document that drop is not a diagnostic API.
   - **(rust-best-practices)**

4. **Health payload is minimal**
   - **File:** `rust/apple_bridge_core/src/http.rs` (`json!({ "ok": true })`)
   - **Issue:** No version, bind info, or provider summary.
   - **Impact:** Fine for PR2b smoke/`curl` if the plan only requires liveness; otherwise clients cannot introspect from `/health` alone.
   - **Not visible in diff — cannot confirm** plan requirements beyond inventory tests expecting OK JSON.
   - **(requesting-code-review)**

### Summary

1. **Highest risk:** `running_status` marks providers `healthy` when only `enabled` — misleading diagnostics (Important).
2. **Second:** HTTP task error handling may skip state updates outside `Running`/`Starting` (Important, partial visibility).
3. **Low:** EOF newlines, ignored shutdown errors, `Drop` wiping `last_error`, minimal `/health` body.

### Verification Note

Assessment is from the **branch diff (with `server.rs` middle truncated)**, diff inventory, inlined `config.rs` context, and review skills only. No tests, builds, or file reads were run. **`justfile`**, **`tests/support/mod.rs`**, **`tests/support/port.rs`**, and the full **`server.rs` `start`/`stop`/generation** hunks were not fully present in the prompt — concurrency and hook changes there were not fully reviewed. **Dirty working tree** noted; uncommitted `justfile` edits are out of scope unless listed only as uncommitted (inventory lists `justfile` as changed on branch).

### Assessment

**Ready to merge: With fixes**

**Reasoning:** HTTP health, bind formatting, error variants, and listed integration tests form a coherent PR2b slice. The provider `healthy` semantics and partial serve-error state reconciliation are the main product/correctness concerns worth fixing or explicitly documenting before merge; remaining items are polish. Confirm truncated `server.rs` and `justfile` hunks in CI/reviewer pass do not introduce additional phase races.

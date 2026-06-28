Reading the full prompt for the complete diff and inlined skills.
# Code review: `feat/pr2b-http-health`

**Base:** `main`  
**Merge base:** `7f2eac04d25a4949a2797d3d4f5f8d0fa6c3345a`  
**HEAD:** `654ae08b7614d52868b477995a3f0d9f3880bcb6`  
**Date:** 2026-06-27  
**Scope:** Committed branch diff vs `main` (dirty working tree noted; no separate uncommitted section in prompt)

---

## Findings

### Important

1. **Running diagnostics mark every provider unhealthy**
   - **File:** `rust/apple_bridge_core/src/server.rs` (`running_status`)
   - **Evidence:** `healthy` changed from `p.enabled` to `false` for all providers when `running: true`.
   - **Issue:** After a successful start, `ServerStatus` reports the server as running while every `ProviderStatus.healthy` stays `false`, with no in-diff comment that this is temporary until real provider health exists.
   - **Why it matters:** Swift/diagnostics consumers may treat “running” as “providers OK” or surface false alarms in the menu bar.
   - **(rust-best-practices)** (requesting-code-review)

2. **HTTP serve failure may leave runtime state inconsistent**
   - **File:** `rust/apple_bridge_core/src/server.rs` (`start_http_server` task error branch)
   - **Evidence:** On `axum::serve` error, the handler sets `phase = Stopped`, updates `status` via `stopped_status_with_error`, and clears `shutdown_tx` / `server_task` only; `inner.runtime` is not cleared in the visible hunk.
   - **Issue:** If `Runtime` remains in `ServerInner` after the task exits, later `start`/`stop` must rely on `clear_stale_runtime` and related paths (not fully visible in the truncated diff).
   - **Why it matters:** Stale runtime + rebind/port tests passing on happy paths does not prove recovery after an unexpected serve exit.
   - **(rust-best-practices)**

### Minor

3. **Missing trailing newline at EOF**
   - **Files:** `rust/apple_bridge_core/src/error.rs`, `rust/apple_bridge_core/src/http.rs`
   - **Evidence:** Diff hunks end with `\ No newline at end of file`.
   - **Issue:** Inconsistent with typical repo/editor conventions and noisy in future diffs.
   - **(rust-best-practices)**

4. **Untyped JSON for liveness response**
   - **File:** `rust/apple_bridge_core/src/http.rs` (`health` → `Json<Value>` + `json!`)
   - **Issue:** A small `Serialize` struct (e.g. `{ ok: bool }`) would document the contract and avoid `Value` for a fixed shape.
   - **Impact:** Low for PR 2b; contract is still clear from module docs and `health_returns_ok_json`.
   - **(rust-best-practices)**

5. **Repeated `ServerStatus` / provider list construction**
   - **File:** `rust/apple_bridge_core/src/server.rs` (`initial_status`, `running_status`, `stopped_status_with_error`)
   - **Issue:** Three near-identical mappings over `enabled_providers` increase drift risk (already visible in `healthy` differing only in `running_status`).
   - **(rust-best-practices)**

### Not visible in diff — cannot confirm

- Full `start` / `stop` / `AlreadyRunning` / `start_generation` / `StartCancelled` logic in `server.rs` (diff truncated mid-`create_server`).
- Committed `justfile` changes (listed in inventory, no hunk in prompt).
- Whether negative paths (e.g. non-`/health` routes) need tests for this PR.

---

## Summary

1. **Highest risk:** Running server status with all providers `healthy: false` may mislead upstream UI/diagnostics unless deliberately documented and consumed as “health not implemented yet.” `(rust-best-practices)`
2. **Second:** Unexpected HTTP task exit clears task handles but may not clear `runtime` in the visible path—confirm lifecycle cleanup in the truncated `server.rs` hunks. `(rust-best-practices)`
3. **Low:** EOF newlines and small API/DRY nits in new HTTP/error surface. `(rust-best-practices)`

**Positive signals from diff/inventory (not findings):** Loopback host validation remains in `config.rs` context; `bind_address` brackets IPv6 literals; dedicated errors `BindFailed` / `RuntimeFailed` / `StartCancelled` with display tests; integration tests cover health JSON, `::1`, port reuse, bind failure, and stop-during-start (`test-driven-development`).

---

## Verification Note

Assessment is based only on the provided diff (with `server.rs` truncated), diff inventory, existing `config.rs` context, and review skills referenced in the prompt. No tests, builds, linters, or file reads were run per review contract. CI should validate `just test-rust` / integration behavior; truncated lifecycle and `justfile` hunks could not be fully judged here.

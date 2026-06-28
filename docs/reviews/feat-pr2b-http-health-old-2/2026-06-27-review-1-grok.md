Reading the full review prompt for the complete diff and inlined skills.
# Code review — `feat/pr2b-http-health` vs `main`

**Date:** 2026-06-27  
**Base:** `main` (`7f2eac04`)  
**HEAD:** `7f2eac04` (no committed delta; findings below are from **uncommitted** working tree changes)

---

## Strengths

- Clear server lifecycle model with `ServerPhase`, `start_generation`, and generation checks after async bind — sensible way to handle races between `start`, `stop`, and in-flight bind. `(rust-best-practices)`
- Shutdown path (`take_shutdown_parts`, `run_shutdown`, graceful axum shutdown) is structured and `Drop` on `ServerHandle` attempts cleanup — important for UniFFI-owned handles. `(rust-best-practices)`
- `bind_address` brackets IPv6 literals; tests move off fixed port `3020` to ephemeral ports — reduces CI flakiness. `(rust-best-practices)`
- New `CoreError` variants with dedicated `Display` tests match existing error patterns. `(test-driven-development)`
- HTTP serve failures update `last_error` and phase when still `Running` — operators get signal instead of silent failure. `(rust-best-practices)`

---

## Findings

### 1. `start()` can return `Ok(())` when the server never reaches `Running`

- **Where:** `rust/apple_bridge_core/src/server.rs` (post-bind commit path: generation/phase mismatch branch ending in `Ok(())`)
- **What:** If `stop()` runs during `Starting` (or another race invalidates the start), `start()` aborts the bound listener but returns **`Ok(())`**, not an error, while status stays stopped/`initial_status`.
- **Why it matters:** Swift/FFI callers typically treat `Ok` as “server is up”; this is a silent no-op after a failed or cancelled start and can leave the menu-bar agent thinking MCP is listening when it is not.
- **Fix direction:** Return a distinct error (e.g. cancelled / superseded) or document and test that callers must always check `server_status().running` after `start()`. `(requesting-code-review)` `(rust-best-practices)`

### 2. `stop()` during `Starting` does not coordinate with an in-progress `block_on`

- **Where:** `rust/apple_bridge_core/src/server.rs` (`stop`, `ServerPhase::Starting` arm)
- **What:** `stop()` bumps `start_generation` and sets `Stopped` without waiting for the thread inside `start()` that may still be in `runtime.block_on(start_http_server(...))`.
- **Why it matters:** Relies entirely on the generation check after bind; correct if that check is airtight, but any future change that commits resources before the generation check could widen the race window.
- **Fix direction:** Add an integration test that hammers `start`/`stop` concurrently (or `stop` during slow bind) and assert no listener leak and consistent status. `(test-driven-development)`

### 3. Core HTTP surface not present in the supplied diff

- **Where:** `rust/apple_bridge_core/src/http.rs`, `rust/apple_bridge_core/tests/http_health.rs`, `rust/apple_bridge_core/tests/support/port.rs` (listed in git status but not inlined in the prompt)
- **What:** Branch intent (PR2b HTTP `/health`) cannot be reviewed: route shape, bind host enforcement (`127.0.0.1`), response body/status codes, or health integration tests.
- **Why it matters:** Without `http.rs`, compliance with “localhost only” and MCP health contract is unverified from evidence.
- **Fix direction:** Ensure the full diff includes `http` router, tests, and any `Cargo.toml` dependency changes before merge review. `(requesting-code-review)` `(verification-before-completion)`

### 4. Missing final newlines in Rust sources/tests

- **Where:** `rust/apple_bridge_core/src/error.rs`, `tests/error_display.rs`, `tests/support/mod.rs` (and possibly others)
- **What:** Diff shows `\ No newline at end of file`.
- **Why it matters:** Violates typical repo/editor conventions; noisy in future diffs.
- **Fix:** Restore trailing newlines. `(rust-best-practices)`

### 5. Unrelated doc/tooling churn in the same working tree

- **Where:** `AGENTS.md` (review triage section), `justfile` (`@` on review recipes), `local/review/AGENTS.md`
- **What:** Not required for HTTP health in the Rust core.
- **Why it matters:** Widens review and merge scope; easy to split into a chore commit/PR.
- **Fix direction:** Split or drop from this PR unless intentionally bundled. `(requesting-code-review)`

---

## Summary (highest risk)

1. **`start()` → `Ok` when start was superseded** — highest risk for incorrect “running” assumptions upstream.  
2. **HTTP `/health` implementation and tests absent from review diff** — cannot sign off on PR2b functional requirements.  
3. **Concurrent start/stop behavior** — design looks intentional but needs explicit tests visible in the change set.

---

## Recommendations

- Add (or include in diff) tests for: successful bind + `GET /health`, bind failure → `BindFailed`, and `stop` during `Starting` / generation mismatch semantics for `start()` return value.
- Confirm `Cargo.toml` adds `axum` / `tokio` with versions aligned to `docs/conventions.md` (not shown in diff).

---

## Verification note

Review is **diff- and skills-only**: no tests, builds, or file reads were run. Committed branch vs `main` is **empty**; assessment is based on uncommitted hunks provided. **`http.rs`, `http_health.rs`, `port.rs`, and dependency manifest changes were not in the prompt**, so health endpoint behavior, localhost binding, and dependency wiring were **not** assessed. CI must run `just lint-rust && just test-rust` before merge.

---

## Assessment

**Ready to merge?** **No**

**Reasoning:** Server lifecycle and error typing look thoughtfully implemented in `server.rs`, but the review packet omits the HTTP module and health tests that define PR2b, and `start()` success semantics after a cancelled start are ambiguous and risky for FFI callers. Address or test the `Ok`-on-superseded path and include the full HTTP diff for a complete review.

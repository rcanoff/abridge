# Code Review: `feat/pr2b-http-health`

**Base:** `main`  
**Merge base:** `7f2eac04d25a4949a2797d3d4f5f8d0fa6c3345a`  
**HEAD:** `dd6d2a6b00f3c9c9a7d8afd77ac1d7837bf21c4b`  
**Date:** 2026-06-27

### Strengths

- PR 2b scope is narrow: dedicated `http` module with documented `GET /health` liveness contract (`rust/apple_bridge_core/src/http.rs`).
- New operational errors (`BindFailed`, `RuntimeFailed`, `StartCancelled`) are wired for UniFFI and covered by display tests listed in the diff inventory (`error_display.rs`).
- Integration tests align with AGENTS verification expectations: health JSON, IPv6 loopback, port-in-use bind failure, stop/rebind, and stop-during-start (`http_health.rs`, `server_lifecycle.rs`).
- Loopback validation in `config.rs` explicitly allows `::1`, consistent with `health_on_ipv6_loopback` in the inventory.
- Tooling docs and `lint-rust` now include formatting checks (`AGENTS.md`, `justfile`).

### Findings

#### Important

1. **`just fmt-check-rust` vs documented command** (conventions)
   - **File:** `justfile` (fmt-check-rust recipe)
   - **Evidence:** Recipe runs `cargo fmt --all -- --check`; `AGENTS.md` documents `cargo fmt --all --check` (no `--` separator).
   - **Issue:** Drift between agent/docs source of truth and the recipe may confuse contributors and copy-paste verification steps.
   - **Why it matters:** Verification matrix tells agents to trust `just lint-rust`; a subtle fmt invocation mismatch can cause “works in CI vs locally” confusion if someone runs the documented raw command instead of `just`.

#### Minor

1. **Missing EOF newlines** (conventions)
   - **Files:** `AGENTS.md`, `justfile` (hunk ends with `\ No newline at end of file` on `rebuild` target)
   - **Issue:** Files still lack a trailing newline after this change.
   - **Why it matters:** Noisy diffs and occasional tooling complaints; small polish gap on a branch that otherwise adds EOF newlines across several Rust modules.

2. **Untyped health JSON body** (rust-best-practices)
   - **File:** `rust/apple_bridge_core/src/http.rs` (health handler returns `Json<Value>` via `json!({ "ok": true })`)
   - **Issue:** Liveness payload is correct but ad hoc `serde_json::Value` instead of a small `Serialize` struct.
   - **Why it matters:** Low risk for a one-field response; a named type would lock the contract and simplify future schema changes without behavior change today.

3. **`provider` field still `#[allow(dead_code)]`** (rust-best-practices)
   - **File:** `rust/apple_bridge_core/src/server.rs` (visible hunk on `ServerInner`)
   - **Issue:** Provider is stored but not used in the HTTP-only slice shown; attribute suppresses warnings rather than integrating or documenting deferral.
   - **Why it matters:** Acceptable for incremental PRs; worth a one-line comment that routing to `ProviderBridge` lands in a later PR so reviewers do not assume wiring is missing by mistake.

### Summary (highest risk first)

1. Documented `cargo fmt --all --check` vs `just fmt-check-rust` using `cargo fmt --all -- --check` — align recipe and `AGENTS.md` (conventions).
2. Core `server.rs` lifecycle implementation (bind, runtime, stop/cancel, condvar usage) was **truncated in the supplied diff** — could not assess deadlocks, lock ordering, or error paths there from this review packet alone.
3. EOF newlines on `AGENTS.md` / `justfile` — trivial hygiene (conventions).

### Verification Note

Review performed **only** from the diff inventory, visible hunks, existing-code note (“all configured context paths are already in the diff”), and review contract skills references. **No** tests, builds, linters, or file reads were run.

**Could assess:** `http.rs` route surface; new `CoreError` variants; loopback/`::1` config; test inventory for health/bind/lifecycle/cancel; `justfile`/`AGENTS.md` tooling changes; partial `server.rs` structure (phases, `Arc<Mutex<…>>`, condvar, tokio runtime fields, `StartInProgressGuard` start — implementation body **not** in the provided diff).

**Could not assess:** Full `server.rs` start/stop/bind/shutdown logic; changes to `uniffi-bindgen.rs`, `provider_bridge.rs`, `config_validation.rs`, and test `support/*` helpers (listed in inventory but hunks not present or truncated); whether Swift FFI callers block appropriately on `start_server` (no Swift diff); runtime logging of bind addresses or tokens (not visible in hunks).

### Assessment

**Ready to merge: Unclear from packet alone**

**Reasoning:** Visible pieces match PR 2b (health endpoint, operational errors, strong integration-test list). The truncated `server.rs` diff is where concurrency and lifecycle correctness live; treat alignment of `fmt-check-rust` with docs as a quick pre-merge fix. Re-review or CI is needed for the unseen server lifecycle implementation before a confident merge call.

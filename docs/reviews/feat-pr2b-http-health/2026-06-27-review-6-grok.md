Reading the full prompt for the complete diff and inlined skills.
# Code Review: feat/pr2b-http-health

**Base:** `main`  
**HEAD:** `4ce4eacf76e5fc3c77c509244eb56009fefe8627`  
**Date:** 2026-06-27

### Strengths

- Clear PR 2b liveness contract: `GET /health` returns `{"ok": true}` with a focused `http::router()` module (`rust/apple_bridge_core/src/http.rs`).
- `CoreError` extended with bind, runtime, and start-cancel variants plus dedicated `error_display` tests in the inventory — aligns with observable server failures (rust-best-practices).
- Integration coverage listed for health JSON, IPv6 loopback, port reuse after stop, bind contention, stop-during-start, and concurrent start — matches HTTP + lifecycle risk (test-driven-development).
- `test-sync` feature + `#[cfg(any(test, feature = "test-sync"))] pub mod test_sync` separates integration-test seams from `cfg(test)` on the library artifact — sensible for `tests/` binaries (rust-best-practices).
- Tooling aligned: `just test-rust` / `just lint-rust` pass `--features test-sync`; `fmt-check-rust` folded into `lint-rust` and documented in `AGENTS.md`.

### Findings

#### Important

_No Important findings with citeable evidence in the non-truncated diff hunks._

#### Minor

1. **Release artifact should never enable `test-sync`**
   - **File:** `rust/apple_bridge_core/src/lib.rs` (hunk exporting `pub mod test_sync` behind `feature = "test-sync"`).
   - **Issue:** The feature gates test-only `start_test_sync` hooks in the same crate Swift links via UniFFI; an accidental `--features test-sync` on `build-rust` would ship those symbols.
   - **Why it matters:** Test seams in production binaries widen the attack and ABI surface.
   - **Fix:** Document in crate/build scripts that only test/lint recipes may enable the feature, or harden the release build path so the feature cannot be enabled there.
   - (rust-best-practices)

2. **Missing EOF newlines called out in diff metadata**
   - **File:** `rust/apple_bridge_core/Cargo.toml` (hunk ends with `\ No newline at end of file`); same marker appears for the `uniffi-bindgen` `[[bin]]` path in the inventory.
   - **Issue:** `fmt-check-rust` is new on this branch; files still flagged without trailing newlines in the diff may fail the new check or churn formatting-only CI.
   - **Why it matters:** New fmt gate makes newline omissions visible failures.
   - **Fix:** Ensure those paths end with a newline so `cargo fmt --check` stays green.
   - (rust-best-practices)

3. **`/health` behavior beyond GET not specified in tests**
   - **File:** `rust/apple_bridge_core/src/http.rs`; test inventory lists only `health_returns_ok_json`, `health_on_ipv6_loopback`, port/bind/lifecycle cases — no wrong-method or unknown-path case.
   - **Issue:** Axum will 404/405 by default; that is fine, but the liveness contract is only asserted for successful GET.
   - **Why it matters:** Low risk for 2b; future auth/MCP routing may want explicit expectations for non-GET on `/health`.
   - **Fix:** Optional follow-up test for `POST /health` or unknown routes if you want the contract frozen in CI.
   - (test-driven-development)

### Summary

1. Highest residual risk is in **`server.rs` and test support code** — not present in the supplied diff body; lifecycle and HTTP wiring cannot be reviewed here.
2. **`test-sync` on release builds** is the main policy gap visible in `lib.rs`.
3. **Fmt/newline hygiene** on `Cargo.toml` (and related bin path) should match the new `fmt-check-rust` gate.

### Verification Note

Review used only the branch diff inventory, the non-truncated diff hunks (`AGENTS.md`, `justfile`, `Cargo.toml`, `config.rs`, `diagnostics.rs`, `error.rs`, `http.rs`, `lib.rs`, EOF-only files), and inlined review/skills instructions. **No tools, builds, tests, or file reads were run.**

**Could not assess from the prompt:** `rust/apple_bridge_core/src/server.rs` (diff truncated at that file), `rust/uniffi-bindgen.rs`, integration test bodies (`http_health.rs`, `server_lifecycle.rs`, `error_display.rs`, `tests/support/*`), and any changes to `provider_bridge.rs` / `config_validation.rs` beyond what appears in the inventory. Bind/listen address enforcement, Tokio runtime ownership, graceful shutdown, port release ordering, and UniFFI error mapping may live there — **not visible in diff — cannot confirm** correctness or gaps.

### Assessment

**Ready to merge: Uncertain from diff alone**

**Reasoning:** Visible pieces (health route, errors, `test-sync` wiring, tooling, test inventory) fit PR 2b HTTP health intent. Merge readiness depends on `server.rs` and integration tests, which were not inlined; CI on this branch remains the authoritative check for those paths. Address Minor items 1–2 if not already fixed in the truncated hunks.

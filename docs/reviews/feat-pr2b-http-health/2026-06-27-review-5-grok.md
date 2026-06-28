# Code review: `feat/pr2b-http-health`

**Base:** `main`  
**Merge base:** `7f2eac04d25a4949a2797d3d4f5f8d0fa6c3345a`  
**HEAD:** `edd39d77f15e39e17f31ef50ccb82199a3706699`  
**Date:** 2026-06-27

---

## Findings

### Important

1. **Server bind and lifecycle logic not fully reviewable from the prompt** (rust-best-practices)  
   - **File:** `rust/apple_bridge_core/src/server.rs` (hunk after `struct StartInProgressGuard`)  
   - **Issue:** The branch diff truncates before the bulk of `server.rs` (~111 → ~398 lines). Start/stop, bind, runtime teardown, lock ordering, and `StartInProgressGuard` behavior cannot be verified from the supplied diff.  
   - **Why it matters:** This PR’s risk is concentrated in concurrency and port lifecycle; assertions about deadlocks, leaked runtimes, or incorrect phase transitions would be speculative without that hunk.  
   - **Fix:** N/A for reviewer; human reviewer or CI should treat full `server.rs` as mandatory reading before merge.

### Minor

2. **Health response uses untyped JSON** (rust-best-practices)  
   - **File:** `rust/apple_bridge_core/src/http.rs` (new file, `health` handler and `router`)  
   - **Issue:** `async fn health() -> Json<Value>` with `json!({ "ok": true })` instead of a small `Serialize` struct (e.g. `{ ok: bool }`).  
   - **Why it matters:** Contract is fixed for PR 2b; a typed response prevents accidental field renames and documents the liveness shape at compile time.  
   - **Fix:** Introduce a dedicated response type and return `Json<HealthResponse>`.

3. **`provider` still only marked `#[allow(dead_code)]`** (rust-best-practices)  
   - **File:** `rust/apple_bridge_core/src/server.rs` (visible hunk on `ServerInner`)  
   - **Issue:** `provider: Arc<dyn ProviderBridge>` is stored but not referenced in the visible HTTP wiring (`http::router()` has only `/health`).  
   - **Why it matters:** Acceptable for a skeleton PR if intentional; otherwise it signals incomplete integration and may hide missing wiring later.  
   - **Fix:** If intentional, a brief comment tying storage to a future MCP route PR reduces “forgotten field” risk (optional doc-only).

4. **Nested `just` in `lint-rust`** (rust-best-practices)  
   - **File:** `justfile` (`lint-rust` recipe)  
   - **Issue:** `lint-rust` invokes `just fmt-check-rust` instead of inlining `cargo fmt --all --check`.  
   - **Why it matters:** Extra process spawn and duplicate `_rust-workspace` guard; low risk, slightly harder to read than a single recipe block.  
   - **Fix:** Inline fmt-check in `lint-rust` or use a private recipe without re-invoking `just`.

---

## Strengths

- **HTTP liveness surface is minimal and documented** — `http.rs` module docs state `GET /health` → `{"ok": true}` for PR 2b (`rust/apple_bridge_core/src/http.rs`).  
- **UniFFI-facing errors extended for real failure modes** — `BindFailed`, `RuntimeFailed`, `StartCancelled` in `error.rs` with dedicated display tests in the diff inventory (`error_display.rs`). (test-driven-development)  
- **Integration-style test coverage matches PR themes** — inventory lists health JSON, IPv6 loopback, port-in-use bind failure, stop/rebind, stop-during-start, and concurrent start while stop awaits (`http_health.rs`, `server_lifecycle.rs`). (test-driven-development)  
- **Tooling aligned with verification matrix** — `fmt-rust`, `fmt-check-rust`, and `lint-rust` including fmt-check documented in `AGENTS.md` and `justfile`.  
- **Loopback host validation unchanged but consistent with IPv6 test** — `is_loopback_host` includes `::1` in `config.rs`; `health_on_ipv6_loopback` in test inventory.

---

## Summary (highest risk first)

1. Truncated `server.rs` diff prevents substantive review of lifecycle, binding, and lock/runtime interaction.  
2. Typed health JSON response is a small hardening opportunity on the only public HTTP route in this PR.  
3. `lint-rust` → `just fmt-check-rust` is a minor maintainability nit.  
4. Stored but unused `provider` in visible `ServerInner` hunk is acceptable only if explicitly skeleton-scoped.

---

## Verification note

Assessment is based on the **committed diff fragments**, **diff inventory**, and **tests-added list** in the prompt only. No tests, builds, or linters were run. The middle of `server.rs` and changes to `rust/uniffi-bindgen.rs` are **not present** in the inlined diff; behavior there is **not confirmed**. Inventory entries for `config_validation.rs`, `provider_bridge.rs`, and test `support/*` imply existing harnesses but were not re-reviewed line-by-line in this pass. CI is expected to validate `just lint-rust && just test-rust` per `AGENTS.md`.

---

## Assessment

**Ready to merge: With human pass on full `server.rs`**

**Reasoning:** Visible pieces (health route, error variants, fmt/lint wiring, and the listed integration tests) fit PR 2b scope and show solid test intent. The review cannot sign off on the core server lifecycle implementation because that diff was truncated; merge confidence depends on reading the complete `server.rs` hunk and green CI, not on gaps visible in the prompt alone.

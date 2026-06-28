# Code review — `feat/pr2b-http-health`

**Base:** `main`  
**Merge base:** `7f2eac04d25a4949a2797d3d4f5f8d0fa6c3345a`  
**HEAD:** `3257b11d5eea97524721ba719fcd6d69bb74eff5`  
**Date:** 2026-06-27  
**Note:** Working tree reported dirty; review is based on committed diff vs `main` (middle of `server.rs` and other hunks truncated in the prompt).

---

### Strengths

- Typed errors for bind, runtime, and cancelled start with dedicated display tests (`error.rs` hunks; inventory: `error_display.rs::*`).
- Loopback binding stays aligned with existing `validate_config` / `is_loopback_host` (`config.rs` context; `bind_address` IPv6 bracket formatting in `server.rs` diff).
- HTTP surface is minimal: `/health` → `{ "ok": true }` (`http.rs`).
- Integration coverage matches risky areas: health JSON, IPv6 loopback, port rebind after stop, bind failure, stop-during-start lifecycle (diff inventory).
- Graceful shutdown path uses oneshot + `axum::serve` + `with_graceful_shutdown`; unexpected serve exit logs and updates status when phase is Running/Starting (`server.rs` `start_http_server` task).

---

### Findings

#### Important

1. **`local/review/` tooling bundled with PR2b core work** (requesting-code-review)  
   - **Evidence:** Diff inventory lists `local/review/bin/review.sh`, `review_lib.py`, `config.toml`, `hooks/pre-push`, `reviewer.grok.md`, `skills.toml`, selftest, README, and paths under `Users/rcanoff/Projects/apple-bridge/local/review/…` alongside `rust/apple_bridge_core/*` and `justfile`.  
   - **Issue:** Agent review harness and pre-push hook behavior ship in the same changeset as HTTP health / server lifecycle. That mixes product/runtime concerns with local developer workflow and expands review and CI surface without an obvious link to PR2b acceptance criteria.  
   - **Why it matters:** Reviewers and merge gates must treat two unrelated systems as one PR; risk of committing machine-local paths or config that `AGENTS.md` treats as local-only.

2. **HTTP serve error path may leave runtime state attached** (rust-best-practices)  
   - **Evidence:** In `start_http_server`’s spawned task, on `serve` error the diff clears `shutdown_tx`, `server_task`, sets `phase`/`status`, but the hunk does not show `runtime.take()` or `clear_stale_runtime` on that path (`server.rs` error branch in diff).  
   - **Issue:** If the listener task exits with an error while `ServerInner.runtime` still holds a `Runtime`, a subsequent `start()` might hit stale state unless another code path always clears it.  
   - **Why it matters:** Port “stuck” or inconsistent phase after crashy shutdown is exactly what `stop_releases_port_for_rebind` is meant to guard; error-path cleanup is not visible in the provided hunk.  
   - **Limitation:** Truncated `server.rs` — cannot confirm compensating logic in `start()`/`stop()`/`clear_stale_runtime`.

#### Minor

3. **Missing final newlines** (rust-best-practices / conventions)  
   - **Evidence:** Diff marks `\ No newline at end of file` on `rust/apple_bridge_core/src/error.rs` and `rust/apple_bridge_core/src/http.rs`.  
   - **Issue:** Inconsistent with typical repo formatting and noisy in future diffs.

4. **`AGENTS.md` review-triage section unrelated to HTTP health** (requesting-code-review)  
   - **Evidence:** `AGENTS.md` hunk adds “Review triage (when asked to check a review)” table and rules.  
   - **Issue:** Useful doc, but orthogonal to PR2b; increases doc churn on a runtime PR.  
   - **Impact:** Low if intentional repo-wide doc update; otherwise consider splitting.

5. **`justfile` change not shown in branch diff excerpt** (requesting-code-review)  
   - **Evidence:** Listed in inventory; no hunk in supplied diff.  
   - **Issue:** Cannot verify recipes align with new Rust integration tests or review hook without the hunk.

---

### Recommendations

- Split or clearly justify `local/review/*` (and absolute-path inventory entries) vs `apple_bridge_core` HTTP/lifecycle changes before merge.
- In truncated `server.rs`, confirm serve-error and cancelled-start paths always clear `runtime` (or document why `clear_stale_runtime` is sufficient).
- Restore EOF newlines on `error.rs` and `http.rs`.

---

### Summary (highest risk)

1. Scope: `local/review` tooling + core Rust server in one diff (inventory).  
2. Possible runtime/task cleanup gap on HTTP serve failure (visible `server.rs` hunk only).  
3. `justfile` and full `start`/`stop`/`Drop` logic not in prompt — lifecycle correctness not fully auditable here.

---

### Assessment

**Ready to merge: With fixes** (or **split PR**)  

**Reasoning:** The HTTP health and lifecycle direction looks sound from visible hunks and the integration test inventory, with loopback config already enforced upstream. The main merge risk is scope (local review harness + doc edits with core server work) and incomplete visibility into full shutdown/start error paths in `server.rs`.

---

### Verification note

Assessed only from diff hunks, diff inventory, existing `config.rs` context, and review contract skills tags — **no** tests, builds, linters, or file reads. Middle of `server.rs`, `justfile`, all of `tests/support/*`, and uncommitted dirty changes were **not** in the supplied diff; findings on those areas are explicitly limited or marked inconclusive. CI remains the authority for `just test-rust` / clippy.

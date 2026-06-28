Reading the full prompt and inlined skills to produce the review from the diff only.
# Code review — `feat/pr2d-bearer-auth`

**Base:** `main`  
**Merge base / HEAD:** `d1916864ab1fbad1103f1bb91dde697d14e57944`  
**Date:** 2026-06-27  
**Scope:** Committed diff (empty) + uncommitted working tree (partial diff in prompt)

---

### Strengths

- Rust auth behavior is backed by explicit integration tests in the inventory: empty/whitespace token rejection, health without auth, MCP 401 without/wrong token, and authenticated MCP reaching the stub (`http_auth.rs`, `config_validation.rs`). (requesting-code-review)
- Bearer validation appears pushed into Rust config (`config.rs` per inventory), consistent with “Rust owns server behavior” and localhost MCP hard rules in project conventions. (requesting-code-review)
- New `KeychainService.swift` and `KeychainServiceTests.swift` are wired into the app and test targets in the visible `project.pbxproj` hunks, so the token storage path is intended to compile in CI once committed. (swift-testing-pro)
- `ServerServing` / `ServerService` / `ServerStore` and Rust `server.rs` / `http.rs` / `auth.rs` / `mcp.rs` are all in the change set, which matches an end-to-end bearer flow (Swift supply token → UniFFI config → HTTP gate) rather than Rust-only auth. (requesting-code-review)

---

### Findings

#### Critical

1. **No committed branch diff vs `main`**
   - **Evidence:** “Branch diff (committed changes vs main)” is empty; HEAD equals merge base.
   - **Issue:** Merging the branch as-is would not land bearer auth; all work is still uncommitted WIP.
   - **Why it matters:** Review and CI target the branch tip, not only the dirty tree, unless this WIP is committed before merge.
   - (verification-before-completion)

#### Important

2. **`project.yml` not in diff inventory**
   - **Evidence:** Inventory lists `AppleBridge.xcodeproj/project.pbxproj` and new Keychain files; no `project.yml` entry.
   - **Issue:** If Keychain sources were added only via manual `pbxproj` edits, `xcodegen generate` may drop them on the next regen.
   - **Why it matters:** Drift between generated project and repo conventions breaks contributor workflow and CI project structure.
   - **Fix:** Ensure `project.yml` includes `KeychainService.swift` and `KeychainServiceTests.swift` if the repo uses XcodeGen as the source of truth.
   - **Note:** Not visible in diff — cannot confirm whether `project.yml` was updated outside the provided hunks.

3. **Generated UniFFI Swift bindings touched**
   - **Evidence:** Inventory includes `AppleBridge/Services/apple_bridge_core.swift` (generated per AGENTS.md).
   - **Issue:** Hand-editing generated bindings instead of regenerating via `just build-rust` risks skew with the Rust API and silent FFI bugs.
   - **Why it matters:** “Never edit generated code” is a hard rule; bearer token fields on config types must match UniFFI output exactly.
   - **Fix:** Confirm the diff is regen-only (or no manual edits inside generated regions). 
   - **Note:** File content not in provided diff — cannot confirm manual vs regenerated changes.

4. **Token handling in Swift/Rust — not assessable from prompt**
   - **Evidence:** `KeychainService.swift`, `ServerStore.swift`, `ServerService.swift`, `auth.rs` are in inventory; implementation hunks were truncated.
   - **Issue:** Cannot verify: tokens never logged; bearer compare is timing-safe; token not persisted in Rust logs/errors; Keychain accessibility/class choices suit a menu-bar agent.
   - **Why it matters:** AGENTS.md requires bearer on MCP routes and never logging tokens; auth bugs are high impact on localhost MCP.
   - **Note:** Not visible in diff — cannot confirm violations; treat as mandatory human/CI pass before merge.

#### Minor

5. **Uncommitted review visibility**
   - **Evidence:** Uncommitted diff in prompt truncates after early `project.pbxproj` hunks (“middle truncated”).
   - **Issue:** Line-level review of Swift UI (`MenuBarPopoverView.swift`), concurrency on `ServerStore`, and Rust `auth.rs`/`http.rs` routing cannot be completed from the supplied material alone.
   - **Why it matters:** Findings above for security and FFI may hide in unseen hunks.
   - (requesting-code-review)

6. **Swift test enumeration vs Rust**
   - **Evidence:** “Tests added in diff” names six Rust tests; Swift adds `KeychainServiceTests.swift` and modifies `ServerStoreTests.swift` but no new Swift test names are listed.
   - **Issue:** Unclear whether store start/stop, token missing, and token passed into `ServerConfig` are covered at the Swift layer.
   - **Why it matters:** Rust integration tests do not replace `ServerStore` orchestration tests with mocks (project verification matrix).
   - **Note:** Not visible in diff — cannot confirm absence of tests inside `ServerStoreTests.swift`.

---

### Summary

1. Branch tip has **zero committed changes** relative to `main`; bearer auth exists only as uncommitted work. (verification-before-completion)  
2. **XcodeGen / `project.yml` alignment** for new Keychain files is unconfirmed and is a common footgun when only `pbxproj` changes. (requesting-code-review)  
3. **`apple_bridge_core.swift` changes** must be regen-only; content not shown here. (requesting-code-review)  
4. **Security-sensitive auth/keychain code** is in scope but truncated from the prompt — no line-level sign-off possible. (requesting-code-review)

---

### Recommendations

- Commit the WIP as one or more logical commits on `feat/pr2d-bearer-auth` so CI and reviewers see the full diff at HEAD.
- Re-run review (or self-review) against the full diff for `auth.rs`, `KeychainService.swift`, and `ServerStore` token lifecycle before merge.
- Align `project.yml` with `pbxproj` if XcodeGen is used in this repo.

---

### Assessment

**Ready to merge: No**

**Reasoning:** There is nothing committed on the branch versus `main`, so merge readiness cannot be granted. The inventory and partial `pbxproj` hunks suggest a coherent PR2d bearer-auth slice (Rust tests, Keychain, store/service wiring), but the truncated uncommitted diff prevents validating token safety, FFI regen discipline, and Swift store tests. Re-review after commit with full diff.

---

### Verification note

Assessment is based only on: empty committed diff, merge-base/HEAD metadata, diff inventory, named new tests list, partial uncommitted `project.pbxproj` hunks, AGENTS.md hard rules, and inlined review contract. **No** tests, builds, linters, or file reads were run or used per review constraints. Middle of the uncommitted diff (Swift/Rust implementation) was **not** present in the prompt; any finding without a hunk citation is explicitly marked as not confirmable from the provided evidence.

Reading the full prompt with the complete diff and inlined skills.
# Code review — `feat/pr2d-bearer-auth`

**Base:** `main`  
**Merge base / HEAD (committed):** `d1916864ab1fbad1103f1bb91dde697d14e57944`  
**Date:** 2026-06-27  
**Scope:** Committed diff vs `main` is empty; findings below for **uncommitted** working tree per prompt.

---

### Strengths

- Rust auth behavior is backed by named integration tests in the inventory (`health_does_not_require_auth`, MCP unauthorized/wrong-token/valid-token cases, `rejects_empty_bearer_token`) — aligns with localhost MCP + bearer expectations in project rules.
- Swift side adds dedicated Keychain wiring in the Xcode project (`KeychainService.swift`, `KeychainServiceTests.swift` in `project.pbxproj`) — sensible place for token persistence vs Rust server config.
- Change set spans Rust HTTP/MCP/auth, Swift server orchestration, and UI (`MenuBarPopoverView`) — matches the architecture split (Rust owns server behavior; Swift owns Keychain/UI).

---

### Findings

#### Critical

*None citeable from visible hunks.*

#### Important

1. **No committed branch delta for PR2d**
   - **Evidence:** Branch diff section is empty; HEAD equals merge base in review metadata.
   - **Issue:** Reviewers and CI on the branch name see zero committed bearer-auth work; only a dirty tree carries the feature.
   - **Why it matters:** Merge/PR review and bisect assume commits on `feat/pr2d-bearer-auth`, not only local WIP.
   - (requesting-code-review)

2. **`project.yml` not in diff inventory**
   - **Evidence:** Inventory lists `AppleBridge.xcodeproj/project.pbxproj` and new `KeychainService*.swift`; no `project.yml`.
   - **Issue:** Repo workflow treats `project.yml` → `xcodegen` as the project source of truth (`Agents.md`). PBX-only file adds risk Xcode/project drift on the next regenerate.
   - **Fix:** Add sources to `project.yml` and regenerate, or document why PBX-only is intentional for this repo state.
   - (verification-before-completion / repo conventions)

3. **`apple_bridge_core.swift` listed as changed — nature of edit unknown**
   - **Evidence:** File appears in inventory; no Swift/UniFFI hunks in the truncated uncommitted diff.
   - **Issue:** Hard rule: never hand-edit generated UniFFI bindings. Manual edits here would be wrong; regenerated output from `just build-rust` is expected after Rust API changes.
   - **Not visible in diff — cannot confirm** whether edits are generated or hand-written; treat as merge gate once hunks are available.
   - (Agents.md / conventions)

#### Minor

1. **Review evidence truncated mid-`pbxproj`**
   - **Evidence:** Uncommitted diff ends at `PBXSourcesBuildPhase` / `FBDCC…` with “middle truncated”.
   - **Issue:** Cannot cite line-level issues in `auth.rs`, `http.rs`, `KeychainService.swift`, `ServerStore.swift`, `ServerService.swift`, mocks, or UI from the prompt alone.
   - (requesting-code-review — evidence discipline)

---

### Summary (highest risk)

1. Feature exists only as uncommitted changes; committed branch matches `main`.
2. Possible `project.yml` / `pbxproj` drift for new Keychain targets.
3. UniFFI Swift binding file changed — must be verified as build output, not manual edit (not confirmable from truncated diff).

---

### Verification note

Assessed **only** from: empty committed diff, file/test inventory, partial uncommitted `project.pbxproj` hunks, workspace rules (`Agents.md`), and review contract. **Did not** run tests, builds, or linters; **did not** read repository files or the full offloaded prompt body.

**Could not assess from provided material:** bearer token flow Keychain → `ServerConfig` → Rust, whether tokens are logged anywhere, `ServerStore`/`ServerService` error UX, `MenuBarPopoverView` token display/copy safety, Rust `auth.rs`/`mcp.rs` constant-time or header parsing edge cases, updates to `MockServerService`/`ServerStoreTests`, `http_health`/`server_lifecycle` fixture changes, or whether `apple_bridge_core.swift` matches a fresh UniFFI build.

**Inventory counterevidence (do not re-request without reading implementation):** Rust auth tests listed in “Tests added in diff”; empty bearer rejection test named in `config_validation.rs`.

---

### Assessment

**Ready to merge: No**

**Reasoning:** There is nothing committed on `feat/pr2d-bearer-auth` vs `main` for this review. Uncommitted work looks directionally right (Keychain + Rust auth tests in inventory), but merge readiness needs the full diff, `project.yml` alignment if applicable, confirmation that generated Swift/Rust FFI artifacts were rebuilt—not edited—and line-level review of token handling and server startup paths once complete hunks are available.

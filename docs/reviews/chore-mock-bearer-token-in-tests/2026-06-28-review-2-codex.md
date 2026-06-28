## Review: `chore/mock-bearer-token-in-tests` vs `main` — 2026-06-28

### Findings

#### 1. CI path filters omit generated bridge artifacts, so binding-only changes can skip macOS CI

- **File:** `.github/workflows/ci-macos.yml`
- **Reference:** path filters include `AppleBridge/**`, `AppleBridgeTests/**`, `project.yml`, `AppleBridge.xcodeproj/**`, `rust/**`, `justfile`, `.swiftformat`, `.swiftlint.yml`, and `scripts/ci/**`, but not `AppleBridgeCore/**`.
- **What’s wrong:** This branch changes the generated Swift binding at `AppleBridge/Services/apple_bridge_core.swift`, which is covered, but the project map and build script also use `AppleBridgeCore/` for generated XCFramework output. A future PR that only refreshes `AppleBridgeCore/**` after a UniFFI/native library change would not trigger macOS CI.
- **Why it matters:** UniFFI API changes require `just build-rust` and Swift compile validation. Skipping macOS CI on generated framework changes can let ABI/binding mismatches reach `main`. `(requesting-code-review, rust-best-practices)`
- **Fix:** Add `AppleBridgeCore/**` to the macOS workflow path filters and to `scripts/ci/paths.sh` as Swift/macOS-impacting.

#### 2. Pre-push path classifier has the same generated artifact blind spot

- **File:** `scripts/ci/paths.sh`
- **Reference:** the classifier marks `rust/*`, `AppleBridge/*`, `AppleBridgeTests/*`, `project.yml`, `AppleBridge.xcodeproj/*`, `justfile`, `scripts/ci/*`, `.swiftformat`, `.swiftlint.yml`, and workflow files, but not `AppleBridgeCore/*`.
- **What’s wrong:** Local pre-push verification skips generated framework-only changes.
- **Why it matters:** This weakens the intended “path-aware CI verify” guard for UniFFI/native framework updates, exactly where Swift/Rust integration can break. `(requesting-code-review, rust-best-practices)`
- **Fix:** Treat `AppleBridgeCore/*` as `PATHS_SWIFT_CHANGED=1`, and likely `PATHS_RUST_CHANGED=1` if the intent is to verify generated Rust outputs against source changes.

### Summary

1. The main risk is CI/pre-push coverage: generated `AppleBridgeCore/**` artifacts are out of the trigger/classification paths.
2. I did not find evidence in the diff for missing bearer-token mocks or missing capability/MCP tests; the inventory shows those were added.

### Verification Note

Reviewed only the supplied diff, inventory, existing context, and inlined skills. I did not run tests, builds, linters, shell commands, or inspect files outside the prompt.
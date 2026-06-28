# Review: `feat/pr3a-mcp-read-milestone` vs `main` — 2026-06-28

## Findings

### 1. `AppleBridge/Models/AppSettings.swift:34-37` — persisted port is not range-checked before `UInt16` conversion `(swiftui-pro)`

`init(defaults:)` reads `defaults.integer(forKey: Keys.mcpPort)` and then does `UInt16(storedPort)` whenever the stored value is `> 0`. That conversion traps for values above `65535`, so a corrupted or manually edited default can crash the app during launch restore before any UI appears.

Why it matters: this turns a user-defaults data issue into a startup crash on the main settings path.

Fix: validate the integer range before converting, and fall back to `3020` for out-of-range values.

### 2. `.github/workflows/ci-macos.yml:7-23` — macOS CI can be skipped for tracked Xcode project changes `(requesting-code-review)`

This branch changes `AppleBridge.xcodeproj/project.pbxproj`, but the macOS workflow path filters only include `AppleBridge/**`, `AppleBridgeTests/**`, `project.yml`, `rust/**`, `justfile`, the Swift lint/format configs, `scripts/ci/**`, and the workflow file itself. `AppleBridge.xcodeproj/**` is not included.

Why it matters: a future PR that edits the tracked `.xcodeproj` directly without touching `project.yml` will bypass macOS CI entirely, even though that file affects builds and tests.

Fix: add `AppleBridge.xcodeproj/**` to the `push.paths` and `pull_request.paths` filters, or stop path-filtering that workflow.

### 3. `.githooks/pre-push:12-16` with `.githooks/README.md:10-15` — default “advisory” review mode is not enforced by the hook `(requesting-code-review)`

The README says review failures are advisory by default, but the hook does `exec "$REVIEW_SCRIPT" --hook` in non-strict mode. That means any non-zero exit from `local/review/bin/review.sh` will abort the hook and block the push. The advisory behavior is therefore delegated to an out-of-scope script rather than guaranteed by the hook itself.

Why it matters: the documented contract for default pushes is unstable. A reviewer script regression or environment failure can unexpectedly block pushes even when `REVIEW_STRICT` is unset.

Fix: invoke the review script without `exec`, inspect its exit status, and explicitly swallow failures when `REVIEW_STRICT` is not set.

## Summary

1. `AppSettings` can crash the app on launch if a persisted MCP port is out of `UInt16` range.
2. macOS CI path filters miss `AppleBridge.xcodeproj/**`, so project-file-only changes can slip past CI.
3. The new pre-push hook does not itself guarantee the documented advisory review behavior.

## Verification Note

Assessed only from the provided diff, inventory, existing context, and inlined skills. I could evaluate Swift/Rust logic, workflow/path-filter behavior, and hook control flow from the patch itself. I could not confirm behavior inside `local/review/bin/review.sh` because it is out of scope and not visible in the diff.
# Review: `feat/pr3a-mcp-read-milestone` vs `main`  
Date: 2026-06-28

## Findings

### 1. `AppleBridge/Models/RemindersPermissionStatus.swift:4-26`, `AppleBridge/Models/PermissionsStore.swift:156-214`, `AppleBridge/Providers/EventKit/EventKitProvider.swift:117-123`
`RemindersPermissionStatusMapper` treats `.writeOnly` as `.authorized`, but the read provider only accepts `.fullAccess`. `(swiftui-pro)`

`RemindersPermissionStatusMapper.map(.writeOnly)` now returns `.authorized`, and `PermissionsStore.remindersAuthorized` uses that status to decide whether to request access in `save()`. But `EventKitProvider.isAuthorized` only returns `true` for `.fullAccess`. That means a user with write-only Reminders permission will see the app treat access as granted, `save()` will skip the permission prompt, and the MCP read tools will still fail at runtime with `permission_denied`.

Why it matters: this creates a false-success permissions state for the milestone’s only shipped capability, `eventkit.reminders.read`.

Fix: make the status model distinguish write-only from full-access for read-gated capabilities, or have `PermissionsStore.save()` / `remindersAuthorized` check the same authorization condition as `EventKitProvider`.

### 2. `AppleBridge/AppleBridgeApp.swift:14-28`
Launch-restore startup errors are immediately overwritten by the follow-up refresh sequence. `(swift-concurrency-pro)`

In `AppleBridgeApp.init()`, the launch task does:

1. `await settingsStore.performLaunchRestoreIfNeeded()`
2. `await serverStore.refreshBearerToken()`
3. `await serverStore.refreshStatus()`

If `performLaunchRestoreIfNeeded()` calls `ServerStore.startServer(...)` and startup fails, `ServerStore` sets `runState = .error(...)`. But the next `refreshStatus()` asks `ServerService` for status; when no handle exists, `ServerService.refreshStatus()` returns `.stopped`, which clears the error state and hides the launch failure.

Why it matters: a failed persisted restore at app launch becomes invisible to the UI, making the new auto-restore behavior hard to diagnose.

Fix: only run the post-restore refreshes when restore did not already attempt startup, or preserve existing `.error` state when `refreshStatus()` sees a stopped server immediately after a failed launch restore.

### 3. `.github/workflows/ci-macos.yml:6-15`, `.github/workflows/ci-rust.yml:6-13`, `scripts/ci/paths.sh:12-25`
The new CI path filters do not cover several files that now control CI and lint behavior. `(requesting-code-review)`

`ci-macos.yml` only triggers for `AppleBridge/**`, `AppleBridgeTests/**`, `project.yml`, and `rust/**`; `ci-rust.yml` only triggers for `rust/**`; `scripts/ci/paths.sh` uses the same narrow classification. But this branch also introduces `.swiftformat`, `.swiftlint.yml`, `justfile`, `scripts/ci/pre-push-verify.sh`, and workflow files themselves as part of the verification system.

Why it matters: future changes to lint rules, task wiring, pre-push verification, or workflow definitions can merge without the affected workflow running at all.

Fix: add the CI-control files to the workflow `paths:` filters and to `scripts/ci/paths.sh` classification so config-only CI changes still exercise the relevant pipeline.

## Summary

1. The new Reminders permission model can report read access as granted while the MCP read tools still fail under write-only authorization.
2. Auto-restore startup failures can be erased during app launch, leaving the server stopped with no visible error.
3. The CI gating added in this branch has blind spots for its own config files, so verification changes can bypass CI.

## Verification Note

Assessment is based only on the provided diff, diff inventory, existing context, and inlined skills. I did not run tests, builds, linters, shell commands, or inspect files outside the prompt.
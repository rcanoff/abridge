# Review: `feat/pr3a-mcp-read-milestone` vs `main`  
Date: 2026-06-28

## Findings

### `AppleBridge/AppleBridgeApp.swift` and `AppleBridge/Views/MenuBarPopoverView.swift`
**Issue:** Persisted `mcpEnabled` no longer causes the server to start after relaunch. `(swiftui-pro)`

**Evidence:** `AppleBridgeApp` now restores `AppSettings` and only calls `serverStore.refreshBearerToken()` / `serverStore.refreshStatus()` in `.onAppear` and on app activation, but never calls `startServer()` when `appSettings.mcpEnabled` is already `true`. In the same diff, `MenuBarPopoverView` removes the old start/stop button entirely and replaces it with a `Settings…` button.

**Why it matters:** A user can enable MCP, quit, relaunch, and end up with settings that say the server is enabled while the server is actually stopped. That is a behavioral regression for a menu bar agent that is expected to keep its local bridge available once enabled.

**Fix:** On launch, if `appSettings.mcpEnabled` is `true`, start the server with the saved port and capabilities instead of only refreshing status.

### `AppleBridge/Providers/EventKit/EventKitProvider.swift`
**Issue:** Read tools accept `.writeOnly` EventKit authorization as sufficient for listing reminders. `(swift-concurrency-pro)`

**Evidence:** `isAuthorized` returns `true` for both `.fullAccess` and `.writeOnly`, and both implemented operations are read operations: `list_lists` and `list_reminders`.

**Why it matters:** `writeOnly` is not enough to read reminder lists or reminder contents. This will either fail at runtime in confusing ways or expose the wrong permission state in the UI and MCP responses.

**Fix:** Require read-capable authorization for these operations, which for this milestone should be `fullAccess` only.

### `AppleBridge/Models/PermissionsStore.swift`
**Issue:** Selecting only unshipped capabilities still triggers Apple permission requests, but those selections are never persisted and remain permanently “pending”. `(swiftui-pro)`

**Evidence:** `save()` requests access whenever `needsAppleAccess()` sees any checked capability at all; `savedIDsAfterSave()` drops every unshipped capability; and `hasPendingChanges()` explicitly treats checked unshipped capabilities as differing from saved state. The catalog marks all non-`read` reminder capabilities as `shipped: false`.

**Why it matters:** A user who checks only blocked capabilities like `Create` will be prompted for Reminders access even though MCP cannot enable anything from that save, and the UI will continue to show unsaved changes after saving. That is a broken permissions workflow, not just a cosmetic issue.

**Fix:** Base the Apple access request and save/pending logic on shipped capabilities only, or explicitly persist blocked selections as draft state if the intended UX is to remember them.

## Summary

1. Persisted MCP enablement does not restart the server on app relaunch, so the app can advertise “enabled” while serving nothing.
2. EventKit read APIs are incorrectly allowed under `.writeOnly`, which is the wrong authorization model for this milestone’s read tools.
3. The permissions flow for unshipped capabilities is internally inconsistent: it asks for Apple access, saves nothing, and leaves the UI in a perpetual pending state.

## Verification Note

Assessed only from the provided diff, inventory, existing context, and inlined skills. I did not run builds, tests, or inspect any files outside the prompt.
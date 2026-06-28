# Review conversation — feat/settings-liquid-glass-ui
**Agent:** codex
**Base:** main
**Started:** 2026-06-28

> **For the implementer:** Reply under open threads before the next review.
> Use `### Reply · implementer` with **Disposition:** `fixed` | `not-fixed` | `disagree` | `partial` and one line why (+ file/line if fixed).
> Do not edit reviewer messages. Do not renumber threads.

## Run log
| Run | Date | HEAD | Open | Resolved | New |
|-----|------|------|------|----------|-----|
| 1 | 2026-06-28 | dd4e333 | 2 | 0 | 2 |
| 2 | 2026-06-28 | 4294d38 | 0 | 2 | 0 |

## Thread 1 — Token reset can re-enable unauthorized capabilities

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Models/SettingsStore.swift`
**Skills:** swift-concurrency-pro, swiftui-pro

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `applySavedCapabilities(remindersAuthorized:)` was changed to gate server capabilities through `appSettings.serverEnabledMCPCapabilityIDs(remindersAuthorized:)`, but `resetBearerToken()` still restarts with `appSettings.enabledMCPCapabilityIDs`:
  `await serverStore.resetBearerToken(port: appSettings.mcpPort, enabledCapabilities: appSettings.enabledMCPCapabilityIDs, restartIfRunning: appSettings.mcpEnabled)`.
- **Related diff:** `AppSettings.serverEnabledMCPCapabilityIDs(remindersAuthorized:)` returns `[]` when Reminders access is not granted, and `SettingsStoreTests.applySavedCapabilitiesOmitsShippedCapabilitiesWithoutRemindersAccess` validates that gating for `applySavedCapabilities`.
- **Issue:** Resetting the bearer token while the server is enabled can restart the server with saved Reminders capabilities even when Reminders access is currently not granted.
- **Why it matters:** This bypasses the branch’s new permission gating path and can leave MCP advertising/enabling `eventkit.reminders.read` after access is revoked or not granted.
- **Fix:** Route every server restart/start path that applies saved capabilities through the same authorization-aware capability list, including token reset. If `SettingsStore` cannot know authorization directly, pass it from the view/store layer as this diff does for `applySavedCapabilities`.

### Reply · implementer · run 1 · 2026-06-28
**Disposition:** fixed
Injected `RemindersPermissionChecking` into `SettingsStore`; all start/restart paths (`applyMCPEnabledChange`, `applyPortChange`, `resetBearerToken`, `performLaunchRestoreIfNeeded`) now use `serverEnabledCapabilities` via `serverEnabledMCPCapabilityIDs(remindersAuthorized:)`. Tests: `resetBearerTokenOmitsShippedCapabilitiesWithoutRemindersAccess`, `performLaunchRestoreOmitsShippedCapabilitiesWithoutRemindersAccess` (`4294d38`).

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** `resetBearerToken()` now passes `enabledCapabilities: serverEnabledCapabilities`, and `serverEnabledCapabilities` calls `appSettings.serverEnabledMCPCapabilityIDs(remindersAuthorized: permissionService.currentStatus().grantsReadAccess)`.
- **Note:** The restart/start paths shown in the diff now use the authorization-aware capability list.

## Thread 2 — Unshipped capabilities are now persisted as saved permissions

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Models/PermissionsStore.swift`
**Skills:** swiftui-pro, swift-testing-pro

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `setChecked(_:for:)` now calls `persistCapabilities()` immediately, and `persistCapabilities()` saves `checkedCapabilityIDs` verbatim: `appSettings.saveCapabilityIDs(checkedCapabilityIDs)`.
- **Related diff:** The previous `save()` path filtered selections through `PermissionsDerivation.savedIDsAfterSave(from:)`, which kept only shipped capabilities. The new test `setCheckedPersistsImmediately` explicitly expects both `"read"` and `"create"` to be saved.
- **Issue:** Selecting an unshipped capability such as `"create"` now persists it into saved settings, even though the MCP server still filters unshipped capabilities out when computing enabled capabilities.
- **Why it matters:** The stored setting can silently become active later if the catalog marks that capability as shipped, without a fresh user decision at that time. It also removes the previous distinction between “selected but blocked” and “saved/enforced”.
- **Fix:** Persist only shipped capability IDs, or store draft UI selections separately from saved MCP permissions. If unshipped selections should remain visible, keep them in view state rather than `AppSettings.savedCapabilityIDs`.

### Reply · implementer · run 1 · 2026-06-28
**Disposition:** disagree
Intentional product choice: persist all MCP toggle intent in `savedCapabilityIDs`; server still gates runtime via `enabledMCPCapabilityIDs` / `serverEnabledMCPCapabilityIDs` (shipped + authorized only). Auto-activation when a capability ships is desired transparency, not silent surprise.

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Implementer clarified this is intentional product behavior; runtime server exposure remains filtered through `enabledMCPCapabilityIDs` / `serverEnabledMCPCapabilityIDs`.
- **Note:** With that product decision, this is no longer an open review blocker.

## Summary
No open findings.

## Verification Note
Reviewed only the provided diff, inventory, existing code context, and inlined skills. I did not run tests, builds, linters, shell commands, or inspect repository files outside the prompt.
# Launch at Login — Design Spec

**Date:** 2026-06-28  
**Status:** Approved (brainstorming)  
**Issue:** [#39 — Launch at login toggle](https://github.com/rcanoff/apple-bridge/issues/39)  
**PRD:** `docs/prd.md` § Runtime Model, § User Interface  
**Architecture:** `docs/architecture-bootstrap-guide.md` — one-process menu bar model  
**Branch:** `feat/launch-at-login`

---

## Summary

Add an optional **Launch at login** toggle so Apple Bridge starts automatically when the user logs in to macOS. The app remains a **menu bar agent** — no separate daemon or `launchd` service.

Launch at login only brings the **application process** up. **MCP server state is independent**: restore behavior via existing `mcpEnabled` persistence and `SettingsStore.performLaunchRestoreIfNeeded()` is unchanged.

---

## Goals

- Optional launch-at-login toggle, **off by default**
- Register/unregister via `SMAppService.mainApp` (macOS 13+; project targets macOS 26+)
- Persist user preference in `AppSettings` / `UserDefaults`
- On app launch, reconcile persisted preference with `SMAppService.mainApp.status` (system is source of truth)
- Settings UI on MCP tab with helper text clarifying MCP is not auto-enabled
- Swift Testing unit tests with protocol seam — no live `SMAppService` in CI
- Manual smoke: toggle → log out/in → menu bar presence; MCP state matches last session

## Non-goals

- Separate background daemon or XPC service
- Auto-enabling MCP when launch at login is turned on
- Diagnostics, API key hardening, usage logs (separate issues)
- New General settings tab
- Notice when user removes login item in System Settings (silent sync only)

---

## Decisions (brainstorming)

| Topic | Choice |
|-------|--------|
| UI placement | **Startup** section at top of existing **MCP** tab |
| Reconciliation | **System wins** — sync `AppSettings.launchAtLogin` to `SMAppService.mainApp.status` on launch; user re-enables in app if desired |
| Registration failure | **Revert toggle** to off, show error under Startup section |

---

## Architecture

**Approach:** Dedicated service + protocol seam (mirrors `RemindersPermissionChecking`).

```
MCPSettingsView (Startup toggle)
        ↓
SettingsStore.applyLaunchAtLoginChange(_:)
SettingsStore.performLaunchAtLoginReconcileIfNeeded()
        ↓
LaunchAtLoginManaging (protocol)
        ↓
SMAppLaunchAtLoginService → SMAppService.mainApp
        ↓
AppSettings.launchAtLogin (UserDefaults)

AppleBridgeApp.init()
  → performLaunchAtLoginReconcileIfNeeded()   // new
  → performLaunchRestoreIfNeeded()            // existing, unchanged
  → refreshBearerToken / refreshStatus
```

Rust and MCP routing are **unchanged**.

---

## Components

### `AppSettings`

| Property | Key | Default | Notes |
|----------|-----|---------|-------|
| `launchAtLogin` | `launchAtLogin` | `false` | Same `didSet` → `defaults.set` pattern as `mcpEnabled` |

### `LaunchAtLoginManaging` (protocol)

```swift
protocol LaunchAtLoginManaging {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}
```

- `isRegistered` — `SMAppService.mainApp.status == .enabled`
- Production: `SMAppLaunchAtLoginService` in `AppleBridge/Services/`
- Test: `MockLaunchAtLoginService` in `AppleBridgeTests/`

Typed error (e.g. `LaunchAtLoginError`) with user-facing `localizedDescription`. Never log bearer tokens or API keys.

### `SettingsStore`

**New state:**

- `launchAtLoginError: String?` — cleared on successful toggle or reconcile
- `didPerformLaunchAtLoginReconcile: Bool` — idempotency guard (private)
- Injected `launchAtLoginService: any LaunchAtLoginManaging` (default `SMAppLaunchAtLoginService()`)

**`applyLaunchAtLoginChange(_ enabled: Bool) async`**

| Action | Success | Failure |
|--------|---------|---------|
| Enable (`true`) | `register()` → `appSettings.launchAtLogin = true`, clear error | Leave `launchAtLogin` false, set `launchAtLoginError` |
| Disable (`false`) | `unregister()` → `appSettings.launchAtLogin = false`, clear error | Leave `launchAtLogin` true (still registered), set `launchAtLoginError` |

**`performLaunchAtLoginReconcileIfNeeded() async`**

- Invoked from `AppleBridgeApp.init()` only — not from SwiftUI view lifecycle
- Once per process launch (idempotent)
- Compare `launchAtLoginService.isRegistered` with `appSettings.launchAtLogin`
- If different: update `appSettings.launchAtLogin` to match system — **no user notice**
- Clear `launchAtLoginError`

MCP methods (`applyMCPEnabledChange`, `performLaunchRestoreIfNeeded`, etc.) are untouched.

### `AppleBridgeApp.init()`

Extend existing launch `Task` ordering:

1. `performLaunchAtLoginReconcileIfNeeded()` — **before** MCP restore
2. `performLaunchRestoreIfNeeded()`
3. `refreshBearerToken()`
4. `refreshStatus()`

Skip when `isRunningUnitTests` (unchanged guard).

### UI — `MCPSettingsView`

New **Startup** section at the **top** of the form (above Server):

| Control | Behavior |
|---------|----------|
| Toggle **Launch at login** | Binding → `applyLaunchAtLoginChange(_:)` |

**Section footer:**

> Starts Apple Bridge when you log in. MCP server starts only if you left it enabled.

**Error display:** When `launchAtLoginError != nil`, show red caption in Startup section footer (same visual language as MCP server errors in `safeAreaInset`).

---

## Testing

### `AppSettingsTests`

- Fresh `UserDefaults` suite → `launchAtLogin` is `false`
- Set `launchAtLogin = true` → persists across new `AppSettings` instance

### `SettingsStoreTests` (with `MockLaunchAtLoginService`)

| Test | Expectation |
|------|-------------|
| Enable success | `register()` called once; `launchAtLogin` true; error nil |
| Disable success | `unregister()` called once; `launchAtLogin` false |
| Enable failure | `register()` throws; `launchAtLogin` stays false; error set |
| Disable failure | `unregister()` throws; `launchAtLogin` stays true; error set |
| Reconcile: setting on, system off | Setting becomes false; no error |
| Reconcile: setting off, system on | Setting becomes true; no error |
| Reconcile idempotent | Second call is no-op |
| Independence | `launchAtLogin` on + `mcpEnabled` off → `performLaunchRestoreIfNeeded()` does not start server |

### Manual smoke (acceptance criteria)

1. Fresh install → toggle **off**
2. Enable toggle → log out/in or reboot → app in menu bar
3. With MCP **off** → app starts, MCP server **does not** start
4. With MCP **on** → app starts, MCP server restores to running
5. Remove app from System Settings → Login Items → reopen app → toggle shows **off**
6. Setting survives normal app restart
7. No bearer tokens logged

---

## Verification

```sh
just test-swift
just ci   # before merge
```

---

## File touch list (implementation)

| File | Change |
|------|--------|
| `AppleBridge/Models/AppSettings.swift` | `launchAtLogin` property |
| `AppleBridge/Services/LaunchAtLoginManaging.swift` | Protocol + error type |
| `AppleBridge/Services/SMAppLaunchAtLoginService.swift` | Production impl |
| `AppleBridge/Models/SettingsStore.swift` | Reconcile + toggle orchestration |
| `AppleBridge/AppleBridgeApp.swift` | Call reconcile on launch |
| `AppleBridge/Views/Settings/MCPSettingsView.swift` | Startup section |
| `AppleBridgeTests/AppSettingsTests.swift` | Persistence tests |
| `AppleBridgeTests/SettingsStoreTests.swift` | Orchestration + reconcile tests |
| `AppleBridgeTests/MockLaunchAtLoginService.swift` | Test seam |
| `project.yml` | Add `ServiceManagement` framework if required by linker |
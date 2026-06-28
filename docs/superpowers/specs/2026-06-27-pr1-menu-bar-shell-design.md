# PR 1: Menu Bar Shell + Reminders Permission — Design Spec

**Date:** 2026-06-27  
**Status:** Approved  
**PRD:** `docs/prd.md`  
**Architecture reference:** `docs/architecture-bootstrap-guide.md`

---

## Summary

PR 1 delivers a minimal macOS menu bar application that boots, displays reminders permission status, and lets the user grant EventKit reminders access. No Rust, no MCP server, no EventKit data operations.

This is the first in a series of small, precise PRs. Each PR validates one layer before the next is added.

---

## Multi-PR Roadmap

| PR | Scope | Outcome |
|----|-------|---------|
| **PR 1** (this spec) | Menu bar SwiftUI shell, reminders permission only | App boots, shows status, requests access |
| **PR 2** | Rust core + UniFFI + embedded MCP HTTP server | `/health`, bearer token auth, server lifecycle |
| **PR 3+** | EventKit vertical slices | Reminders read → write → calendar → advanced |

### Phasing principle

Bootstrap in thin vertical slices. PR 1 proves app lifecycle and permission UX. PR 2 proves the process model (embedded server, Keychain token, UniFFI bridge). PR 3+ adds EventKit MCP tools one capability at a time.

---

## Goals (PR 1)

- Ship a working macOS menu bar app with no dock icon
- Show current EventKit **reminders** permission status on launch
- Let the user request reminders access from the popover
- Keep Swift code minimal and focused — no architectural scaffolding for future PRs

## Non-goals (PR 1)

- Rust workspace, UniFFI, XCFramework, `justfile`
- MCP server, `/health`, bearer token, Keychain
- Calendar permission (deferred until calendar MCP tools ship)
- EventKit read/write operations (lists, events, reminders)
- Launch at login
- Server/provider status UI placeholders
- Settings persistence (port, token, preferences)
- Provider modules under `Providers/`
- `ServerService`, `KeychainService`, `AppleProviderBridge`

---

## Approach

**Selected: Lean SwiftUI shell (Approach 1)**

Create only the files needed for menu bar + permission flow. Do not pre-scaffold the full architecture guide directory layout. PR 2 will add `Services/`, `Providers/`, and Rust integration as new files.

### Rejected alternatives

| Approach | Reason rejected |
|----------|-----------------|
| Full directory scaffold upfront | Ships unused stubs; violates YAGNI; noisy review |
| AppKit `NSStatusItem` | Extra complexity; conflicts with SwiftUI-first direction |

---

## App Structure

```
AppleBridge/
├── AppleBridgeApp.swift
├── Models/
│   └── AppStore.swift
├── Services/
│   └── RemindersPermissionService.swift
└── Views/
    └── MenuBarPopoverView.swift
```

### Xcode project setup

- New macOS App target: **AppleBridge**
- Interface: SwiftUI
- Language: Swift 6 with strict concurrency checking enabled
- Test target: **AppleBridgeTests** (Swift Testing)
- **Agent (background app):** enable "Application is agent (UIElement)" so the app has no dock icon and lives in the menu bar only

---

## Components

### `AppleBridgeApp`

- `@main` entry point
- Single scene: `MenuBarExtra` with the `bell` system symbol (replaceable later without scope change)
- No `WindowGroup`
- Inject `@Observable` `AppStore` into the popover
- On appear: call `store.refreshStatus()`

### `AppStore`

- `@Observable`, `@MainActor`
- Owns `RemindersPermissionService` (injected or constructed internally for PR 1)
- Published state:
  - `permissionStatus: RemindersPermissionStatus`
  - `isRequestingPermission: Bool`
  - `lastError: String?` (user-visible, copyable)
- Actions:
  - `refreshStatus()` — reads current authorization from EventKit
  - `requestAccess()` — triggers permission request; sets `isRequestingPermission` during the call

### `RemindersPermissionStatus`

App-level enum mapping EventKit authorization to UI states:

| Value | Meaning | UI treatment |
|-------|---------|--------------|
| `unknown` | Not yet queried | Neutral text; refresh on launch |
| `notDetermined` | User has not been prompted | Show **Grant Access** button |
| `authorized` | Full reminders access granted | Green status; hide button |
| `denied` | User denied access | Red status; show guidance to open System Settings (macOS will not re-prompt) |
| `restricted` | Parental controls or policy block | Red status; explain access is restricted |

### `RemindersPermissionService`

- Owns a single `EKEventStore` instance
- `currentStatus() -> RemindersPermissionStatus` — maps `EKEventStore.authorizationStatus(for: .reminder)` (or macOS 14+ reminders-specific API) to the app enum
- `requestAccess() async throws` — calls `requestFullAccessToReminders(completion:)` (macOS 14+) or the appropriate API for the deployment target
- No business logic beyond permission inspection and request
- Errors propagate as typed Swift errors; `AppStore` maps them to `lastError` strings

### `MenuBarPopoverView`

Minimal popover content:

```
┌─────────────────────────┐
│  Apple Bridge           │
│                         │
│  Reminders Access       │
│  ● Authorized           │
│                         │
│  [ Grant Access ]       │
└─────────────────────────┘
```

- **Title:** "Apple Bridge"
- **Status line:** "Reminders Access" + current status text with color (green / amber / red)
- **Grant Access button:** visible when status is `.notDetermined`; also offer "Open System Settings" when `.denied`
- **Error text:** show `lastError` in red with `.textSelection(.enabled)` when present
- **Loading state:** disable button and show progress while `isRequestingPermission` is true

No server status, port configuration, bearer token, provider list, or grayed-out placeholders.

---

## Data Flow

```
App launch
  → MenuBarExtra appears
    → AppStore.refreshStatus()
      → RemindersPermissionService.currentStatus()
        → EKEventStore.authorizationStatus(for: .reminder)
      → UI updates

User taps "Grant Access"
  → AppStore.requestAccess()
    → RemindersPermissionService.requestAccess()
      → EKEventStore.requestFullAccessToReminders(...)
    → AppStore.refreshStatus()
    → UI updates
```

No local persistence. EventKit and macOS System Settings are the source of truth for permission state.

---

## Error Handling

| Situation | Behavior |
|-----------|----------|
| Permission request fails | Set `lastError` with a human-readable message; keep button enabled for retry |
| Permission denied | Show denied status; link/button to open System Settings → Privacy → Reminders |
| Permission restricted | Show restricted status; no retry button |
| EventKit API error on status read | Set `lastError`; show unknown status |

Never crash on permission paths. Never silently swallow errors.

---

## Testing

### Swift Testing (`AppleBridgeTests`)

- **Status mapping:** verify `RemindersPermissionService` (or a testable mapper) converts each `EKAuthorizationStatus` to the correct `RemindersPermissionStatus`
- **AppStore:** verify `refreshStatus()` updates `permissionStatus`; verify `isRequestingPermission` toggles during request (use a mock service protocol if needed to avoid live EventKit calls in CI)

### Manual smoke test

1. Launch app — menu bar icon appears, no dock icon
2. Open popover — status shows `.notDetermined` or current system state
3. Tap **Grant Access** — macOS permission dialog appears
4. Grant access — status updates to `.authorized`, button hides
5. Revoke in System Settings, relaunch — status shows `.denied` with settings guidance

### CI note

EventKit permission dialogs cannot run in unattended CI. Unit tests must use mocks/protocols for the permission service seam. Manual smoke test is required before merge.

---

## Deployment Target

- **macOS 26+** per `architecture-bootstrap-guide.md`
- Use `requestFullAccessToReminders` and modern EventKit reminders authorization APIs (available on this target)

---

## PR 2 Preview (not in scope)

PR 2 will add per `architecture-bootstrap-guide.md`:

- `rust/` workspace and `apple_bridge_core` crate
- UniFFI bindings and XCFramework
- `ServerService`, `KeychainService`, `AppleProviderBridge` (stub)
- MCP HTTP server on `127.0.0.1` with `/health` and bearer token auth
- Menu bar popover gains server status section (running/stopped, port)

PR 1 files (`AppStore`, `MenuBarPopoverView`) will be extended in PR 2 — not rewritten.

---

## Success Criteria (PR 1)

- [ ] App launches as a menu bar-only agent (no dock icon)
- [ ] Popover shows accurate reminders permission status on launch
- [ ] User can request reminders access from the popover
- [ ] Denied state shows actionable guidance (System Settings)
- [ ] Swift tests pass for status mapping and store behavior
- [ ] No Rust, MCP, or EventKit data code in the diff

---

## Open Items

None. Scope is fully defined for PR 1 implementation.
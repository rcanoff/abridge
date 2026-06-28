# Review: `feat/pr2c-swift-server-ui` vs `main`  
Date: 2026-06-27

## Findings

### Important: Server lifecycle and status checks run synchronously on the main actor, so the menu bar UI can freeze during start/stop/refresh `(swift-concurrency-pro)`
- Evidence:
  - [`AppleBridge/Models/ServerStore.swift:27-63`](#/Users/rcanoff/Projects/apple-bridge/AppleBridge/Models/ServerStore.swift) makes `startServer()`, `stopServer()`, and `refreshStatus()` `@MainActor` work.
  - [`AppleBridge/Services/ServerService.swift:17-66`](#/Users/rcanoff/Projects/apple-bridge/AppleBridge/Services/ServerService.swift) keeps the service itself `@MainActor` and calls synchronous UniFFI entry points: `createServer`, `startServer`, `stopServer`, and `serverStatus`.
  - [`AppleBridge/Views/MenuBarPopoverView.swift:71-80`](#/Users/rcanoff/Projects/apple-bridge/AppleBridge/Views/MenuBarPopoverView.swift) wraps the button actions in `Task { ... }`, but those tasks still invoke synchronous `@MainActor` methods.
  - [`AppleBridge/AppleBridgeApp.swift:11-19`](#/Users/rcanoff/Projects/apple-bridge/AppleBridge/AppleBridgeApp.swift) also refreshes server status on `onAppear` and app activation from the UI path.
- Why it matters: `Task {}` does not move synchronous main-actor work off the UI thread. If Rust server creation, bind, shutdown, or status lookup takes noticeable time, the menu bar popover and activation path will hang.
- Fix: move FFI lifecycle/status work behind an async boundary off the main actor, then hop back to `MainActor` only to publish `runState`, `isStarting`, and `lastError`.

### Important: `AGENTS.md` is now packaged into both the app bundle and the test bundle as a runtime resource `(requesting-code-review)`
- Evidence:
  - [`AppleBridge.xcodeproj/project.pbxproj`](#/Users/rcanoff/Projects/apple-bridge/AppleBridge.xcodeproj/project.pbxproj) adds `AGENTS.md in Resources` for both targets via `125C9D7A345204E4FD23420B /* Resources */` and `E051CE23017C6484EAA68864 /* Resources */`.
  - The same file is added under the `AppleBridge` and `AppleBridgeTests` groups, which caused it to be treated as target content rather than repo-only instructions.
- Why it matters: this ships internal agent/developer instructions inside distributable artifacts for no product benefit. That exposes internal process/security guidance unnecessarily and makes bundle contents noisier and less intentional.
- Fix: exclude `AGENTS.md` from target resources and keep it as repository-only metadata.

## Summary
1. The highest-risk issue is synchronous Rust server work on `MainActor`, which can block the menu bar UI during startup, shutdown, and status refreshes.
2. The project is also bundling `AGENTS.md` into runtime artifacts, which leaks internal instructions without any app-facing purpose.

## Verification Note
Assessment is based only on the provided diff, diff inventory, existing code context, and inlined skills. I could not confirm actual startup latency, full Rust server behavior beyond the provided `config.rs`, or any unchanged tests outside the prompt.
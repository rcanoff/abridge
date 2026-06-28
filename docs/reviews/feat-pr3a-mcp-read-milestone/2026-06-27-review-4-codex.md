# Review: `feat/pr3a-mcp-read-milestone` vs `main` — 2026-06-28

## Findings

### Critical

#### `AppleBridge/Providers/AppleProviderBridge.swift:3-20`, `AppleBridge/Providers/EventKit/EventKitProvider.swift:12-55`
`AppleProviderBridge` is marked `@unchecked Sendable` and calls `EventKitProvider.handle(...)` directly from the synchronous Rust FFI callback path, but `EventKitProvider` and `LiveEventKitStore` touch `EKEventStore`/EventKit objects with no actor or thread confinement. The diff shows no main-actor hop before `eventKitProvider.handle(...)`, and `LiveEventKitStore` is also marked `@unchecked Sendable`, so MCP requests can drive EventKit from arbitrary Rust worker threads. That is exactly the kind of unsafe sync/async bridge the concurrency rules call out, and it risks crashes or undefined behavior once real MCP traffic hits the provider. Fix by isolating EventKit access to `@MainActor` and explicitly hopping to the main actor from the FFI bridge instead of relying on `@unchecked Sendable`. `(swift-concurrency-pro)`

### Important

#### `AppleBridge/AppleBridgeApp.swift:23-33`
`restoreServerOnLaunchIfNeeded()` is only invoked inside `MenuBarPopoverView.onAppear`. With `MenuBarExtra`, that content does not mount until the user opens the popover, so persisted `mcpEnabled` state will not actually restore the server at process launch. The branch adds `SettingsStore.restoreServerOnLaunchIfNeeded()` and tests for that store method, but the app wiring here delays it until UI interaction, which breaks the advertised “restore on launch” behavior. Move launch restore into an app-lifecycle path that runs during startup, not a popover view lifecycle callback. `(swiftui-pro)`

## Summary

1. EventKit is being called from an unchecked cross-thread FFI path without main-actor isolation, which is a correctness bug under Swift concurrency.
2. Persisted MCP server restore is wired to popover `onAppear`, so the server does not actually come back until the user opens the menu bar UI.

## Verification Note

Assessment is limited to the committed diff, diff inventory, existing code context, and inlined skills. I also reviewed the separate uncommitted patch: it appears to address both findings above, and I did not identify an additional distinct issue in that WIP diff from the material provided.
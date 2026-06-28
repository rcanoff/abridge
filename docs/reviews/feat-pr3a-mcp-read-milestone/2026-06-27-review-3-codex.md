# Review: `feat/pr3a-mcp-read-milestone` vs `main`  
Date: 2026-06-28

## Findings

### 1. `AppleBridge/AppleBridgeApp.swift:20-31` — persisted MCP auto-start is tied to popover appearance, not app launch `(swiftui-pro)`
`restoreServerOnLaunchIfNeeded()` is only called inside `MenuBarPopoverView.onAppear`:

```swift
MenuBarExtra("Apple Bridge", systemImage: "bell") {
    MenuBarPopoverView(...)
        .onAppear {
            ...
            Task {
                await settingsStore.restoreServerOnLaunchIfNeeded()
                await serverStore.refreshBearerToken()
                await serverStore.refreshStatus()
            }
        }
}
```

That means a saved “server enabled” state is not restored when the menu bar app launches; it is restored only after the user opens the popover for the first time. This breaks the intended lifecycle implied by `restoreServerOnLaunchIfNeeded()` and by the new persisted `mcpEnabled` setting, because clients cannot connect until the UI is manually opened.

Fix: move the launch restore into app startup, not a view appearance callback tied to popover presentation.

### 2. `AppleBridge/Providers/AppleProviderBridge.swift:3-20` and `AppleBridge/Providers/EventKit/EventKitProvider.swift:16-54` — `@unchecked Sendable` is masking unsynchronized EventKit access `(swift-concurrency-pro)`
The new provider stack marks multiple reference types as `@unchecked Sendable`:

- `AppleProviderBridge: ProviderBridge, @unchecked Sendable`
- `LiveEventKitStore: EventKitStoreing, @unchecked Sendable`
- `EventKitProvider: @unchecked Sendable`

`LiveEventKitStore` holds a mutable `EKEventStore`, and `EventKitProvider`/`AppleProviderBridge` expose synchronous entry points that the Rust server can call from arbitrary background threads. There is no actor isolation or locking around the shared `EKEventStore`, so the branch is asserting thread safety without proving it. That is exactly the kind of case `@unchecked Sendable` is meant to avoid, not paper over.

Why it matters: concurrent MCP tool calls can race through the same EventKit objects, which risks undefined behavior or framework-level crashes.

Fix: isolate EventKit access behind a single actor / main-actor boundary, or create a synchronization strategy that makes the Sendable claim actually true.

## Summary

1. The server restore path does not actually run at app launch; it runs only when the menu bar popover is opened.
2. The new EventKit bridge relies on `@unchecked Sendable` for shared framework objects without any visible synchronization.

## Verification Note

Assessment is limited to the provided diff, diff inventory, existing code context, and inlined skills. I did not run tests, builds, or inspect any files outside the prompt, so I could not confirm runtime behavior beyond what is visible here.
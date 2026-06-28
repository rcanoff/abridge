# Review: feat/pr3a-mcp-read-milestone → main

Date: 2026-06-28

## Findings

### 1. Swift actor-bound APIs now return non-`Sendable` types across concurrency boundaries

- **File:** `AppleBridge/Models/ServerRunState.swift`
- **Evidence:** The diff changes `enum ServerRunState: Equatable, Sendable` to `enum ServerRunState: Equatable`, while `ServerServing.refreshStatus() async -> ServerRunState` is awaited from `@MainActor` `ServerStore`.
- **Also visible:** `ServerOperationError` and `KeychainError` similarly lose `Sendable` conformance in `ServerService.swift` and `KeychainService.swift`.
- **What’s wrong:** These values cross actor or async protocol boundaries. Under strict Swift concurrency, removing `Sendable` from actor-returned state and thrown error payload types can produce concurrency diagnostics or force unsafe workarounds later.
- **Why it matters:** This project explicitly enables strict concurrency and the branch adds more actor-isolated server control flow. The prior `Sendable` conformances were the correct model for value-only status and error structs.
- **Fix:** Restore `Sendable` on `ServerRunState`, `ServerOperationError`, `KeychainError`, and likely `RemindersPermissionStatus` unless there is a concrete reason they cannot be transferred safely. `(swift-concurrency-pro)`

### 2. EventKit reminder fetch can block the main actor for up to five seconds

- **File:** `AppleBridge/Providers/EventKit/EventKitProvider.swift`
- **Evidence:** `EventKitProvider` and `LiveEventKitStore` are `@MainActor`; `fetchReminders(matching:)` calls `EventKitReminderFetch.waitForCompletion`, whose `defaultTimeout` is `5`, then spins `RunLoop.main` until completion or timeout.
- **What’s wrong:** An authenticated MCP `tools/call` for reminders can synchronously occupy the main actor for up to five seconds. Pumping the run loop reduces total deadlock risk, but it also creates reentrancy risk and still leaves the menu bar/settings UI vulnerable to stalls.
- **Why it matters:** This is server-driven work, not direct UI work. A slow or stalled EventKit callback should not monopolize the app’s main actor, especially because the provider bridge explicitly routes Rust background callbacks onto the main actor.
- **Fix:** Avoid blocking the main actor for the full fetch lifecycle. Push the synchronous FFI boundary away from UI isolation, or restructure the provider bridge so EventKit callback waiting happens off-main while only the EventKit calls that truly require main isolation hop to `MainActor`. `(swift-concurrency-pro)`

## Summary

1. Re-add `Sendable` to value types crossing actor and async boundaries.
2. Rework the synchronous EventKit fetch path so MCP reads cannot stall the main actor.

## Verification Note

This review is based only on the supplied diff, inventory, existing context, and inlined skills. I did not run tests, builds, linters, shell commands, or inspect files outside the prompt.
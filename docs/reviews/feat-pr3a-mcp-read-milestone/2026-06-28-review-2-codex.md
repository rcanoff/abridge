# Review: feat/pr3a-mcp-read-milestone → main

Date: 2026-06-28

## Findings

### 1. Generated UniFFI Swift binding is modified in the branch

- **File:** `AppleBridge/Services/apple_bridge_core.swift`
- **Evidence:** The diff changes `ServerConfig` and adds `FfiConverterSequenceString` in `AppleBridge/Services/apple_bridge_core.swift`, while `AGENTS.md` says: “Never edit generated code — `AppleBridgeCore/`, `apple_bridge_core.swift`.”
- **What’s wrong:** This branch includes changes to a generated file that project rules explicitly mark as off-limits.
- **Why it matters:** Hand-edited generated bindings can drift from Rust UniFFI output and create hard-to-debug FFI ABI/schema mismatches.
- **Fix:** Regenerate bindings from the Rust UniFFI source and commit only generated output if the project intentionally tracks it; otherwise exclude this file from hand-authored PR diffs. `(requesting-code-review)`

### 2. `EventKit` reminder fetch can freeze the app’s main actor for up to 30 seconds

- **File:** `AppleBridge/Providers/EventKit/EventKitProvider.swift`
- **Evidence:** `EventKitReminderFetch.defaultTimeout = 30`; `waitForCompletion()` spins `RunLoop.main.run(...)` until completion; `EventKitProvider` is `@MainActor`; `AppleProviderBridge.callProvider()` synchronously hops provider calls onto the main actor.
- **What’s wrong:** A stalled `fetchReminders` call blocks the main actor synchronously until timeout.
- **Why it matters:** MCP requests can make the menu bar app unresponsive for up to 30 seconds, including settings, permission UI, and any main-actor state updates. The added `StalledEventKitStore` test confirms the timeout path exists, but not the UI impact.
- **Fix:** Avoid blocking the main actor for the full timeout. Prefer an async provider path or a bounded background bridge that returns quickly while EventKit work completes cooperatively. `(swift-concurrency-pro)`

### 3. Token reset loses the active token during restart bookkeeping

- **File:** `AppleBridge/Services/ServerService.swift`
- **Evidence:** `resetBearerToken()` sets `currentBearerToken = token`, then calls `stop()` when `handle != nil`; `stop()` clears `currentBearerToken = nil`.
- **What’s wrong:** The service briefly records the rotated token, then immediately clears it during stop.
- **Why it matters:** Code that asks `activeBearerToken()` between reset and restart will see `nil`, and the store may need to fall back to keychain loading instead of using the just-rotated token. This is especially fragile around restart failures.
- **Fix:** Either stop before assigning `currentBearerToken`, or preserve the rotated token after `stop()` when reset succeeds. `(swift-concurrency-pro)`

## Summary

1. The branch changes generated UniFFI Swift bindings despite project rules forbidding edits to generated code.
2. EventKit reminder reads can block the main actor for up to 30 seconds.
3. Bearer token reset clears the newly rotated in-memory token during restart handling.

## Verification Note

Review is based only on the supplied diff, inventory, inlined skills, and context. I did not run tests, builds, linters, shell commands, or inspect files outside the prompt.
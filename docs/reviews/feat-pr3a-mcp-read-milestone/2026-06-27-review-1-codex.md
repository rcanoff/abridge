# Review: `feat/pr3a-mcp-read-milestone` vs `main`
Base: `main`  
Date: 2026-06-28

## Findings

### 1. Token reset while running will leave the server stopped instead of restarting `(swift-concurrency-pro)`
**File:** `AppleBridge/Models/ServerStore.swift` (`startServer()` guard and `resetBearerToken()`)

`resetBearerToken()` calls `serverService.resetBearerToken()`, then immediately calls `startServer(...)` when `restartIfRunning` is true. But `startServer(...)` bails out if `runState == .running`, and `resetBearerToken()` never updates `runState` before that call.

```swift
guard !isStarting, runState != .running, runState != .starting else { return }
```

At the same time, `ServerService.resetBearerToken()` stops the live server handle when one exists:

```swift
if handle != nil {
    try await stop()
}
```

That means a reset from the running state can end with:
- `ServerStore.runState` still saying `.running`
- the underlying Rust server already stopped
- the attempted restart skipped by the stale `runState` guard

Why it matters: the Settings UI promises a restart after rotating the token, but the actual result can be silent downtime until the user manually starts the server again.

Fix: capture whether the store was running before reset, update `runState` after the stop, then call `restartServer(...)` or otherwise bypass the stale-state guard during the restart path.

### 2. The Permissions screen cannot persist “disable all capabilities” `(swiftui-pro)`
**File:** `AppleBridge/Views/Settings/PermissionsSettingsView.swift` (save button disable rule)

The save button is disabled whenever `checkedCapabilityIDs` is empty:

```swift
.disabled(isSaving || permissionsStore.checkedCapabilityIDs.isEmpty)
```

But clearing the final enabled capability is a valid state change, and `PermissionsStore.save()` already supports persisting an empty set via `savedIDsAfterSave(from:)`.

Why it matters: if a user previously enabled `read` and then unchecks it, they cannot save that change. The last saved capability remains active in settings and will continue to be enforced on restart.

Fix: disable the button based on `isSaving` and possibly `!permissionsStore.hasPendingChanges`, not on whether the selection is empty.

### 3. Invalid `list_id` arguments are silently widened into “return everything” `(swiftui-pro)`
**File:** `AppleBridge/Providers/EventKit/EventKitProvider.swift` (`parseArguments(_:)`)

`parseArguments(_:)` only errors when the payload is not a JSON object. If `list_id` exists but is the wrong type, the function falls through and returns `nil`:

```swift
if let listID = dictionary["list_id"] as? String {
    return listID
}

if dictionary["list_id"] is NSNull {
    return nil
}

return nil
```

That `nil` is then treated as “no filter” in `reminderPredicate(listID:)`, which fetches reminders from all calendars.

Why it matters: malformed client input such as `{"list_id":123}` does not fail fast. Instead, it broadens scope and returns more reminder data than requested.

Fix: if `list_id` is present and is neither a string nor `null`, return `invalid_arguments` rather than treating it as omitted.

### 4. `initialize` accepts and echoes any client protocol version `(rust-best-practices)`
**File:** `rust/apple_bridge_core/src/mcp/mod.rs` (`handle_initialize`)

The server advertises a fixed protocol constant in `protocol.rs`:

```rust
pub const PROTOCOL_VERSION: &str = "2024-11-05";
```

But `handle_initialize()` does not return that constant reliably. It mirrors whatever the client sent:

```rust
let protocol_version = params
  .get("protocolVersion")
  .and_then(Value::as_str)
  .unwrap_or(PROTOCOL_VERSION);
```

Why it matters: a client can send an unsupported or future version and receive that same version back, making negotiation appear successful when the server has only implemented one protocol level. That can cause subtle interop failures after initialization.

Fix: return the server-supported protocol version, or explicitly validate the client version and reject unsupported values.

## Summary

1. `ServerStore.resetBearerToken()` can stop a running server and fail to bring it back up because restart is gated on stale UI state.
2. `PermissionsSettingsView` blocks saving an empty selection, so users cannot disable the last active capability.
3. `EventKitProvider.parseArguments()` treats an invalid `list_id` type as “no filter”, which can expose all reminders unexpectedly.
4. MCP `initialize` currently mirrors arbitrary client protocol versions instead of negotiating or enforcing the server’s supported version.

## Verification Note

The committed branch diff against `main` is empty in the prompt, so these findings are based on the `Uncommitted changes` diff only. I did not run tests, builds, or inspect repository state outside the provided inventory, diff, and inlined skills.
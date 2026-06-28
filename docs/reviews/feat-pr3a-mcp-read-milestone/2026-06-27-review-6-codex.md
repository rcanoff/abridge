# Review — `feat/pr3a-mcp-read-milestone` vs `main` — 2026-06-28

## Findings

### `rust/apple_bridge_core/src/mcp/mod.rs:81-91, 176-181` — `tools/list` can advertise unusable tools `(rust-best-practices)`
`handle_tools_list()` builds its response from `tools::tools_for_capabilities(&state.enabled_capabilities)` only, while `handle_tools_call()` separately rejects calls when `provider_enabled(state, tool.provider)` is false. That means a config with a disabled `eventkit` provider can still publish `eventkit.reminders.*` in `tools/list`, then fail every call with `provider_disabled`.

Why it matters: MCP clients use `tools/list` as the discoverable contract. Advertising tools that are known to be non-callable is a protocol-level behavior bug, not just a UX issue.

Fix: apply the same provider-enabled filter during `tools/list` generation that `tools/call` already enforces.

### `AppleBridge/Models/PermissionsStore.swift:112-126, 200-221` and `AppleBridge/Views/Settings/PermissionsSettingsView.swift:55-58, 145-166` — blocked selections remain checked after save, but are no longer saveable `(swiftui-pro)`
`save()` persists only shipped capabilities via `savedIDsAfterSave(from:)`, but it never reconciles `checkedCapabilityIDs` to that persisted subset. At the same time, `hasPendingChanges()` ignores unshipped capabilities. So if a user checks `Create` plus `Read`, saves, and only `Read` is persisted, the `Create` toggle stays checked in the UI, `hasPendingChanges` becomes `false`, and the Save button disables.

Why it matters: the settings window can display an unsaved blocked capability as if it were part of the current configuration until the view is reopened, which is incorrect state presentation and makes the UI hard to reason about.

Fix: after a successful save, reset `checkedCapabilityIDs` to the persisted set, or treat unshipped checked items as pending state that must remain actionable.

### `AppleBridge/Providers/EventKit/EventKitProvider.swift:37-48` — reminder fetch timeout is reported as an empty success `(swift-concurrency-pro)`
`LiveEventKitStore.fetchReminders(matching:)` spins the main run loop until either the EventKit callback fires or 30 seconds elapse, then returns `fetched` unconditionally. If the callback never arrives, `done` stays false and the method still returns the default empty array.

Why it matters: a stalled or failed EventKit fetch becomes indistinguishable from “this list has no reminders”, so MCP consumers can receive silently wrong data instead of an error.

Fix: detect deadline expiry and surface a provider error for timeout/stall rather than returning `[]`.

## Summary

1. `tools/list` and `tools/call` disagree about provider enablement, so the server can publish tools it already knows are unusable.
2. Permissions saving leaves blocked toggles visually selected while also removing any way to commit or clear that state in the same session.
3. EventKit reminder fetches can fail silently as empty results, which risks incorrect MCP reads.

## Verification Note

Assessment is limited to the diff, inventory, existing code context, and inlined skills. I could not verify runtime behavior, builds, CI, or any logic not visible in the provided diff.
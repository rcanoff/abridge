# Review: `feat/pr3a-mcp-read-milestone` vs `main`
Base: `main`  
Date: 2026-06-28

## Findings

### 1. Whitespace-padded provider/capability values pass validation but are treated as disabled at runtime `(rust-best-practices)`
**Evidence:** `rust/apple_bridge_core/src/config.rs:43-76`, `rust/apple_bridge_core/src/mcp/mod.rs:175-184`

`validate_config()` trims `enabled_capabilities` and provider names before validating them, but it never rejects or normalizes the original strings. Later, `capability_enabled()` and `provider_enabled()` compare the stored values with exact string equality.

That means a config such as `" eventkit.reminders.read "` or `" eventkit "` is accepted by validation, but `tools/list` and `tools/call` will behave as if the capability/provider is disabled. This is a real runtime mismatch between validation and execution.

Fix: either reject leading/trailing whitespace in `validate_config()` or normalize the stored config values before the server starts.

### 2. The Permissions summary can tell users Apple access is needed even when the selected capability does not require it `(swiftui-pro)`
**Evidence:** `AppleBridge/Models/PermissionsStore.swift:82-136`, `AppleBridge/Views/Settings/PermissionsSettingsView.swift:15-16`

`PermissionsDerivation.appleSummary()` reports `"Reminders — needed"` whenever any capability is checked and Reminders access is not granted. But `requiresAppleAccess(for:)` explicitly filters to shipped capabilities only, and the added test `unshippedOnlySelectionDoesNotRequireAppleAccess` confirms that selecting only `"create"` should not require Apple access.

As a result, if the user checks only an unshipped capability such as Create, the UI summary says Apple access is needed even though `save()` will not request it and MCP will keep it blocked. That is contradictory guidance in the primary settings UI.

Fix: make `appleSummary()` use the same shipped-capability filter as `requiresAppleAccess(for:)`.

### 3. The token reset notice is shown before reset succeeds and remains visible on failure `(swiftui-pro)`
**Evidence:** `AppleBridge/Models/SettingsStore.swift:62-70`, `AppleBridge/Views/Settings/MCPSettingsView.swift:69-84`

`SettingsStore.resetBearerToken()` sets `tokenResetNotice` before calling `serverStore.resetBearerToken(...)`. If keychain rotation or restart fails, `serverStore.lastError` is shown, but the success-oriented notice still says: `"Server will restart with a new token. Update your MCP client."`

This can mislead users into updating clients to a token that was never actually issued or activated.

Fix: set the notice only after a successful reset/restart, or clear it when `serverStore` ends in an error state.

## Summary

1. Validation and runtime behavior disagree for whitespace-padded provider/capability IDs, which can silently disable MCP functionality.
2. The Permissions UI can incorrectly instruct users to grant Reminders access for capabilities that the app itself treats as non-shipping and non-requesting.
3. The MCP token reset flow can display a success notice even when reset failed.

## Verification Note

Assessment is limited to the diff, diff inventory, existing code context, and the inlined skills. I did not run builds, tests, or inspect files outside the provided review material.
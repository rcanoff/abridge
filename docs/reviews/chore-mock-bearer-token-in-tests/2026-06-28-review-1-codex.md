# Review: chore/mock-bearer-token-in-tests vs main (2026-06-28)

## Findings

### 1. Generated UniFFI Swift file is edited directly
- **File:** `AppleBridge/Services/apple_bridge_core.swift`
- **Reference:** diff hunk adds `enabledCapabilities` to `ServerConfig` and adds `FfiConverterSequenceString`.
- **Issue:** The branch modifies generated UniFFI output directly, while `AGENTS.md` hard-rules say “Never edit generated code — `AppleBridgeCore/`, `apple_bridge_core.swift`.”
- **Why it matters:** Manual generated-code edits are brittle: the next `just build-rust` / binding regeneration can overwrite them or produce mismatched FFI if Rust and Swift bindings drift.
- **Fix:** Regenerate bindings from the Rust UniFFI source and commit the generated result, rather than hand-editing `apple_bridge_core.swift`. `(using-superpowers, requesting-code-review)`

### 2. Token reset can rotate persisted credentials before confirming the running server stopped
- **File:** `AppleBridge/Services/ServerService.swift`
- **Reference:** `resetBearerToken()` rotates first, then stops if `handle != nil`.
- **Issue:** `let token = try tokenStore.rotateBearerToken()` happens before `try await stop()`. If stopping the active server fails, Keychain now contains the new token while the still-running server may still be using the old token.
- **Why it matters:** This can leave the UI/client-visible token out of sync with the active MCP server auth token, causing local clients to fail authentication until a successful restart.
- **Fix:** Stop first when a handle exists, then rotate and restart/start as needed, or add rollback/recovery so the persisted token and active server token cannot diverge. `(swift-concurrency-pro, requesting-code-review)`

### 3. Successful token reset message is wrong when MCP is disabled
- **File:** `AppleBridge/Models/SettingsStore.swift`
- **Reference:** `resetBearerToken()` always sets `tokenResetNotice = "Server will restart with a new token. Update your MCP client."` after success.
- **Issue:** `resetBearerToken(... restartIfRunning: appSettings.mcpEnabled)` may be called while MCP is disabled, but the notice still says the server will restart.
- **Why it matters:** The settings UI can tell users a restart happened or will happen when no server is running, which is misleading around credentials and client configuration.
- **Fix:** Set different notice text based on `appSettings.mcpEnabled` / `serverStore.runState`, or only mention restart when a restart was actually requested and completed. `(swiftui-pro, requesting-code-review)`

## Summary

1. Generated UniFFI Swift output appears to be directly edited, violating the project hard rule.
2. Bearer-token rotation can persist a new token before the active server is safely stopped.
3. Token reset success copy is inaccurate when MCP is disabled.

## Verification Note

Reviewed only the provided diff, inventory, existing context, and inlined skills. I did not run tests, builds, linters, shell commands, or inspect files outside the prompt.
# Review: `feat/pr2d-bearer-auth` vs `main`
Base: `main`  
Date: `2026-06-27`

## Findings

### `AppleBridge/Models/ServerStore.swift:24-33, 37-55`
**Incorrect bearer token can be shown after server start because `startServer()` never refreshes `bearerToken`.** `(swiftui-pro)`

`refreshBearerToken()` is the only place that updates `bearerToken`, but `startServer()` calls `serverService.start(...)` directly and only refreshes run status afterward. In `ServerService.start()`, `loadBearerToken()` may create or change the token before building `ServerConfig`, so the server can start with a new token while the UI still shows the old one or `nil`.

Why it matters:
- The menu bar UI is the only visible place exposing the token.
- If the keychain entry is missing or rotated before start, users will copy the wrong credential and fail authentication against `/mcp`.

Fix:
- Refresh `bearerToken` as part of `startServer()` after a successful `start(...)`, or have `start(...)` return the effective token so state and UI stay consistent.

### `rust/apple_bridge_core/src/config.rs:34-38`
**Bearer token validation accepts whitespace-only values.** `(rust-best-practices)`

The new validation checks `if config.bearer_token.is_empty()` only. Unlike `host` and provider names, it does not trim first. A config containing `"   "` passes validation, but `auth::parse_bearer_token()` trims the presented header token and rejects empty results, so the server can be started in a configuration where no client can ever authenticate.

Why it matters:
- This is a configuration bug in the new auth path.
- It creates a self-inflicted denial of service: server boots successfully but all `/mcp` requests are guaranteed to get `401`.

Fix:
- Validate `config.bearer_token.trim().is_empty()` and add a matching test for whitespace-only input.

## Summary

1. The Swift store can display a stale or missing bearer token even after the server starts with a different effective token.
2. The Rust config validator allows whitespace-only bearer tokens, producing a server that starts but can never authenticate clients.

## Verification Note

The committed branch diff against `main` is not visible here because the prompt lists the same SHA for merge base and HEAD; these findings are based on the uncommitted changes section only. I could assess code paths, state flow, and test coverage visible in the prompt, but not behavior outside the provided diff/context.
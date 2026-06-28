# Review: `feat/pr2d-bearer-auth` vs `main`  
Base: `main`  
Date: `2026-06-27`

## Findings

### 1. Running server and displayed token can drift out of sync `(requesting-code-review)`
- Evidence: [AppleBridge/AppleBridgeApp.swift] calls `serverStore.refreshBearerToken()` on every popover appearance and app activation before `refreshStatus()`. [AppleBridge/Models/ServerStore.swift] stores that value in `bearerToken`. [AppleBridge/Services/ServerService.swift] only applies `currentBearerToken` inside `start(host:port:)`, and `refreshStatus()` never reconciles a changed keychain token with a running server.
- What’s wrong: if the keychain value changes while the server is already running, the UI will show the new token but the Rust server will still be enforcing the old one until a restart path happens.
- Why it matters: this makes the only auth credential user-visible but potentially incorrect, which is a functional auth break for any client copying the token from the menu bar.
- Fix: either treat the token as immutable for the lifetime of a running server and stop refreshing it in the UI, or detect token rotation and restart/reconfigure the server before surfacing the new value.

### 2. `401 Unauthorized` responses do not advertise the Bearer challenge `(rust-best-practices)`
- Evidence: [rust/apple_bridge_core/src/auth.rs] `unauthorized_response()` returns status + JSON body only; no `WWW-Authenticate` header is added.
- What’s wrong: bearer-protected endpoints should return a `WWW-Authenticate: Bearer` challenge on `401` so clients can identify the auth scheme correctly.
- Why it matters: some HTTP/MCP clients and generic tooling rely on the challenge header for standards-compliant auth handling; without it, interop is weaker and the failure mode is less machine-readable.
- Fix: add `WWW-Authenticate: Bearer` to the unauthorized response, ideally with an `error="invalid_token"` style challenge if you want stricter RFC 6750 behavior.

### 3. New Swift tests depend on the real macOS keychain instead of an isolated seam `(swift-testing-pro)`
- Evidence: [AppleBridge/Services/KeychainService.swift] directly uses `Security` APIs, and [AppleBridgeTests/KeychainServiceTests.swift] exercises `deleteBearerToken()`, `loadOrCreateBearerToken()`, `loadBearerToken()`, and `saveBearerToken()` against a live keychain namespace.
- What’s wrong: these tests are environment-coupled integration tests inside the regular unit test target, but the diff does not add any isolation for keychain availability, access class behavior, or test-runner-specific failures.
- Why it matters: this makes the Swift test suite more fragile in CI and on developer machines, especially for a security-store dependency that is outside normal in-process state control.
- Fix: keep unit coverage at the `BearerTokenStoring` boundary with mocks/fakes, and move live keychain verification into an explicitly scoped integration/manual test path if you still want end-to-end coverage.

## Summary

1. The highest-risk issue is token drift between the running server and the token shown in the UI.
2. The Rust auth layer is missing the standard Bearer challenge header on `401` responses.
3. The new Keychain tests are coupled to live OS state and are likely to be brittle in normal CI runs.

## Verification Note

The committed branch diff against `main` is empty at the provided `Base`/`Head` SHA, so no committed-change findings were available. The findings above are based only on the uncommitted diff, the inventory, the inlined skills, and the prompt context; no builds, tests, shell commands, or repository reads were performed.
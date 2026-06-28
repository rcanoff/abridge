# Review: `feat/pr2c-swift-server-ui` vs `main`  
Date: 2026-06-27

## Findings

### Important: Server is advertised as usable while every provider call is hard-failed `(requesting-code-review)`
**Evidence**
- [`AppleBridge/Services/ServerService.swift`]( /Users/rcanoff/Projects/apple-bridge/AppleBridge/Services/ServerService.swift ) creates the server with `enabledProviders: [ProviderConfig(name: "eventkit", enabled: true)]`.
- [`AppleBridge/Providers/AppleProviderBridge.swift`]( /Users/rcanoff/Projects/apple-bridge/AppleBridge/Providers/AppleProviderBridge.swift ) implements `callProvider(request:)` by always returning `ok: false` with `{"code":"not_implemented"}`.

**What’s wrong**  
The new UI can start a server that reports as running, but the only enabled provider is a stub that rejects all requests. That makes the server operationally misleading: users can start it successfully, yet every EventKit-backed MCP operation still fails.

**Why it matters**  
This is a user-visible functional regression for the new server controls. “Running” currently means “listening,” not “serving the enabled provider,” which is a bad contract for a menu bar control surface.

**Fix**  
Either wire `AppleProviderBridge` to a real EventKit implementation before enabling `eventkit`, or do not enable/register that provider until the callback is implemented.

### Important: Status/initialization paths can abort the host app instead of surfacing an error `(rust-best-practices)`
**Evidence**
- [`AppleBridge/AppleBridgeApp.swift`]( /Users/rcanoff/Projects/apple-bridge/AppleBridge/AppleBridgeApp.swift ) triggers `Task { await serverStore.refreshStatus() }` on appear and again on `NSApplication.didBecomeActiveNotification`.
- [`AppleBridge/Services/ServerService.swift`]( /Users/rcanoff/Projects/apple-bridge/AppleBridge/Services/ServerService.swift ) calls `serverStatus(handle:)` in `refreshStatus()` and `initLogging()` in `start(host:port:)`.
- [`AppleBridge/Services/apple_bridge_core.swift`]( /Users/rcanoff/Projects/apple-bridge/AppleBridge/Services/apple_bridge_core.swift ) implements both `serverStatus(handle:)` and `initLogging()` with `try! rustCall(...)`, and `uniffiEnsureAppleBridgeCoreInitialized()` uses `fatalError(...)` on contract/checksum mismatch.

**What’s wrong**  
The new UI path eagerly exercises FFI calls that are wired to trap on unexpected Rust/UniFFI failures instead of converting them into typed Swift errors. A checksum mismatch, initialization failure, or unexpected Rust panic will terminate the menu bar app rather than update `lastError`.

**Why it matters**  
The project’s Rust guidance explicitly treats panics on UniFFI-reachable paths as correctness bugs because they can abort the host app. This diff puts those aborting paths directly on app launch/activation and on the new Start Server action.

**Fix**  
Wrap FFI entry points used by the UI in fallible Swift APIs that translate failures into `ServerOperationError`, and avoid calling `try!`/`fatalError` from status or startup flows exposed to the app.

## Summary

1. The branch starts and labels an `eventkit` server as usable even though the provider bridge still rejects every request.
2. The new server status/startup path can crash the host app on FFI initialization/runtime failures instead of reporting an error in the UI.

## Verification Note

Assessed only from the provided diff, inventory, existing code context, and inlined skills. I could not confirm runtime behavior, build success, or whether provider health checks elsewhere compensate for the stubbed `AppleProviderBridge`.
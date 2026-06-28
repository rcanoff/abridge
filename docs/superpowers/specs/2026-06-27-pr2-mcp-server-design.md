# PR 2: MCP Server Bootstrap — Design Spec

**Date:** 2026-06-27  
**Status:** Approved  
**PRD:** `docs/prd.md`  
**Architecture reference:** `docs/architecture-bootstrap-guide.md`  
**Predecessor:** `docs/superpowers/specs/2026-06-27-pr1-menu-bar-shell-design.md`

---

## Summary

PR 2 introduces the embedded MCP server stack in four small PRs. Each PR validates one layer before the next is added. The series ends with a manually started local HTTP server, `/health`, Swift/UniFFI integration, and minimal server status UI. Bearer token auth is deferred to PR 2d.

PR 1 delivered the menu bar shell and reminders permission flow. PR 2 does not add EventKit MCP tools.

---

## Multi-PR Roadmap

| PR | Branch (suggested) | Scope | Outcome |
|----|-------------------|-------|---------|
| **PR 2a** | `feat/pr2a-rust-uniffi-skeleton` | Rust skeleton + UniFFI + `ProviderBridge` mock | Crate builds, UniFFI contract defined, Rust tests pass |
| **PR 2b** | `feat/pr2b-http-health` | HTTP bind + `/health` + graceful shutdown | `curl /health` works while Rust test server runs |
| **PR 2c** | `feat/pr2c-swift-server-ui` | XCFramework + Swift wiring + manual start + popover status | User can start/stop server from menu bar popover |
| **PR 2d** | `feat/pr2d-bearer-auth` | Keychain token + auth middleware + stub `/mcp` | Authenticated routes enforced (future PR) |

### Phasing principle

Same as PR 1: thin vertical slices, precise PRs, reviewable diffs. Auth and auto-start on launch are intentionally deferred to keep PRs small and avoid shipping security plumbing before the HTTP layer is proven.

### Post-PR2 sequence (unchanged from PRD)

| PR | Scope |
|----|-------|
| PR 3+ | EventKit vertical slices — reminders read → write → calendar → advanced |

---

## Approach

**Selected: Full Rust module skeleton in PR 2a (Approach 1)**

Create the architecture guide module layout in PR 2a with real types and stub lifecycle. Defer `auth.rs` to PR 2d and HTTP/`mcp.rs` handler logic to PR 2b. Avoid cramming PR 2a + PR 2b into one PR.

### Rejected alternatives

| Approach | Reason rejected |
|----------|-----------------|
| Minimal crate (few modules only) | PR 2b/2c cause layout churn and noisy diffs |
| PR 2a + PR 2b combined | Violates small-PR preference |

---

## PR 2a: Rust Skeleton + UniFFI (Rust-only)

### Goals

- Add `rust/` workspace and `apple_bridge_core` crate
- Export UniFFI server lifecycle API and provider callback interface
- Implement config validation, typed errors, diagnostics, logging init
- `ServerHandle` state machine without HTTP socket binding
- Rust tests with `MockProviderBridge`
- `justfile` with `test-rust` and `lint-rust` only

### Non-goals (PR 2a)

- HTTP server, axum routes, port binding
- `auth.rs`, bearer token, `mcp.rs` protocol handlers
- `build-macos.sh`, XCFramework, generated Swift bindings
- Swift/Xcode project changes
- `just build-rust`

### Repository additions

```text
rust/
├── Cargo.toml
├── rustfmt.toml
├── build.rs
├── uniffi-bindgen.rs
└── apple_bridge_core/
    └── src/
        ├── lib.rs
        ├── error.rs
        ├── config.rs
        ├── diagnostics.rs
        ├── logging.rs
        ├── providers.rs
        └── server.rs
justfile
```

`auth.rs` and `mcp.rs` are added in PR 2b/2d respectively.

### UniFFI surface

Exported from `lib.rs`:

| Export | Purpose |
|--------|---------|
| `init_logging()` | Initialize `tracing` (no ANSI in FFI context) |
| `create_server(config, provider)` | Validate config, construct `ServerHandle` |
| `start_server(handle)` | Transition to running (no network bind) |
| `stop_server(handle)` | Transition to stopped |
| `server_status(handle)` | Return `ServerStatus` snapshot |

Types: `ServerConfig`, `ProviderConfig`, `ProviderRequest`, `ProviderResponse`, `ServerStatus`, `ProviderStatus`, `CoreError`.

### ServerConfig (PR 2a — no auth)

| Field | Type | Notes |
|-------|------|-------|
| `host` | `String` | Default `127.0.0.1`; reject non-loopback by default |
| `port` | `u16` | Default `3020`; reject `0` |
| `enabled_providers` | `[ProviderConfig]` | Per architecture guide §5 validation matrix (PR 2a rows) |

**No `bearer_token` until PR 2d.** PR 2c Swift wiring uses the PR 2a config shape.

### ProviderBridge

```rust
#[uniffi::export(callback_interface)]
pub trait ProviderBridge: Send + Sync {
    fn call_provider(&self, request: ProviderRequest) -> ProviderResponse;
}
```

- Rust owns routing policy later; PR 2a only defines the callback contract
- `MockProviderBridge` in `#[cfg(test)]` or `tests/` for unit/integration tests
- `create_server` requires a provider instance (box trait object)

### ServerHandle behavior (no HTTP)

| Method | Behavior |
|--------|----------|
| `create_server()` | Validate config; construct handle with `running: false` |
| `start()` | Set `running: true`; update `ServerStatus`; do **not** bind port |
| `stop()` | Set `running: false`; clear running state |
| `status()` | Safe before start, while running, after stop |

PR 2b replaces stub `start()`/`stop()` with real HTTP bind/shutdown while preserving the same UniFFI API.

### Config validation rules

Implement all **PR 2a** rows in `docs/architecture-bootstrap-guide.md` §5 validation matrix. Provider ID shape (lowercase, no whitespace) is defined in `docs/conventions.md` § Providers and operations and enforced via the matrix.

### Error handling

- `thiserror` + `#[derive(uniffi::Error)]` on `CoreError`
- No `unwrap()` / `expect()` on UniFFI-reachable paths
- Return `Result<T, CoreError>` for all user-input paths

### Testing (PR 2a)

| Test | Verifies |
|------|----------|
| Config rejects invalid host/port | Validation matrix (host, port rows) |
| Config rejects invalid provider ID shape | Validation matrix (lowercase, no whitespace) |
| Config rejects duplicate providers | Validation matrix (unique name row) |
| `create_server` with mock provider | Construction |
| Start → status running → stop → status stopped | Lifecycle state machine |
| Mock provider `call_provider` | Callback seam |

Run: `TZ=UTC just test-rust`, `just lint-rust`

### Toolchain

Per architecture guide: Rust edition 2024, MSRV 1.85, UniFFI 0.31 proc-macro mode only (no UDL).

### Success criteria (PR 2a)

- [ ] `cargo test` passes with mock provider
- [ ] `cargo clippy -- -D warnings` passes
- [ ] UniFFI scaffolding generates without manual UDL
- [ ] No Swift files changed
- [ ] No HTTP code in diff

---

## PR 2b: HTTP + `/health` (Rust-only, no auth)

### Goals

- Bind HTTP listener on configured host/port in `ServerHandle::start()`
- `GET /health` → `{"ok": true}` (no auth required)
- Graceful shutdown on `stop()`; release port
- `start()` fails cleanly if port is busy
- Rust integration tests hitting live `/health`

### Non-goals (PR 2b)

- Bearer token auth (PR 2d)
- `GET /status` (optional; defer unless needed for PR 2c)
- `POST /mcp` or MCP protocol handling
- Swift changes
- Keychain

### HTTP stack

- axum 0.8 + tokio runtime owned by `ServerHandle`
- Explicit shutdown signaling (not drop-and-hope)
- Long-running server task started in `start()`, joined/cancelled in `stop()`

### Endpoints (PR 2b)

| Path | Auth | Response |
|------|------|----------|
| `/health` | None | `{"ok": true}` |

All other paths return 404 until later PRs.

### Testing (PR 2b)

- Integration test: start server on ephemeral port, `GET /health`, assert 200 + JSON
- Integration test: `stop()` releases port (subsequent bind succeeds)
- Integration test: double `start()` or bind failure returns `CoreError`

### Success criteria (PR 2b)

- [ ] `curl http://127.0.0.1:3020/health` works when server started via Rust test harness
- [ ] Graceful shutdown verified in tests
- [ ] No Swift changes
- [ ] No auth middleware in diff

---

## PR 2c: Swift Integration + Manual Start UI

### Goals

- Add `build-macos.sh`, `just build-rust`, XCFramework, generated Swift bindings
- Swift services: `ServerService`, stub `AppleProviderBridge`
- Dedicated `ServerStore` (`@Observable`, `@MainActor`) for server UI state
- Extend `MenuBarPopoverView` with minimal server status + manual Start/Stop
- User starts server via button (not auto-start on launch)

### Non-goals (PR 2c)

- `KeychainService`, bearer token, auth UI
- `/mcp` tool implementations
- EventKit provider operations
- Auto-start on app launch (deferred — may change later)
- Launch at login
- Port/token persistence in user settings (hardcode defaults for now)

### Build pipeline additions

```text
AppleBridgeCore/                    # GENERATED — do not edit
rust/build-macos.sh
justfile                            # add build-rust, test-all, etc.
AppleBridge/Services/
  apple_bridge_core.swift           # GENERATED — do not edit
  ServerService.swift
AppleBridge/Providers/
  AppleProviderBridge.swift         # stub only
AppleBridge/Models/
  ServerStore.swift
```

### Swift components

#### `ServerService`

- `@MainActor` wrapper over generated UniFFI API
- `start(port:)` / `stop()` / `status()` 
- Calls `init_logging()` once before first server creation
- Maps `CoreError` to user-visible strings centrally
- Owns `ServerHandle` lifecycle; recreates handle on config change (port change → stop + recreate)

#### `AppleProviderBridge` (stub)

```swift
final class AppleProviderBridge: ProviderBridge {
    func callProvider(request: ProviderRequest) -> ProviderResponse {
        ProviderResponse(
            ok: false,
            payloadJson: "{}",
            errorJson: #"{"code":"not_implemented"}"#
        )
    }
}
```

#### `ServerStore`

- `@Observable`, `@MainActor`
- State: `serverStatus` (stopped/running/starting/error), `host`, `port` (default `127.0.0.1:3020`), `lastError`
- Actions: `startServer()`, `stopServer()`, `refreshStatus()`
- Injects `ServerService` for testing (protocol seam, same pattern as PR 1 `RemindersPermissionChecking`)

#### Popover UI (minimal)

Extend `MenuBarPopoverView` — compose existing `AppStore` (permissions) and new `ServerStore` (server):

```
┌─────────────────────────┐
│  Apple Bridge           │
│                         │
│  Reminders Access       │
│  ● Authorized           │
│                         │
│  Server                 │
│  ● Stopped              │
│  127.0.0.1:3020         │
│                         │
│  [ Start Server ]       │
│                         │
│  <error if any>         │
└─────────────────────────┘
```

**SwiftUI conventions (swiftui-pro):**

- Use `foregroundStyle()` not `foregroundColor()`
- Server error text: `.textSelection(.enabled)`
- Buttons: explicit labels — `Button("Start Server")` / `Button("Stop Server")` (not icon-only)
- Keep permission and server sections in one popover; do not merge `AppStore` and `ServerStore` into one type

**Button visibility:**

| Server state | Button |
|--------------|--------|
| Stopped / error | **Start Server** |
| Running | **Stop Server** |
| Starting | Disabled button + `ProgressView` |

**Lifecycle:**

- App launch does **not** start server
- User taps **Start Server** → `ServerStore.startServer()` → `ServerService` → Rust `start_server`
- User taps **Stop Server** → graceful shutdown
- On popover appear: `refreshStatus()` for both permission and server state

#### `AppleBridgeApp` wiring

- Add `@State private var serverStore = ServerStore()`
- Pass both stores to `MenuBarPopoverView`
- Keep existing permission refresh on appear + `didBecomeActive`

### Default server config (PR 2c)

| Field | Value |
|-------|-------|
| host | `127.0.0.1` |
| port | `3020` |
| enabled_providers | `[{ name: "eventkit", enabled: true }]` (stub; no tools yet) |

### Testing (PR 2c)

| Layer | Tests |
|-------|-------|
| Swift | `ServerStore` with mock `ServerService` — start/stop/status/error paths |
| Swift | Stub bridge compiles and returns `not_implemented` |
| Manual | Start server → `curl http://127.0.0.1:3020/health` → `{"ok": true}` |
| Manual | Stop server → health fails |
| Rust | Existing PR 2a/2b tests still pass |

### Success criteria (PR 2c)

- [ ] `just build-rust` produces XCFramework and Swift bindings
- [ ] App builds and links Rust core
- [ ] Manual start/stop works from popover
- [ ] `/health` responds while running
- [ ] Swift tests pass
- [ ] No Keychain, no bearer token, no `/mcp` tools

---

## PR 2d: Bearer Auth (preview — not in this spec's implementation scope)

Deferred per brainstorming. Documented here for continuity.

### Goals (future)

- Add `bearer_token` to `ServerConfig`
- `KeychainService` in Swift — load or create token
- `auth.rs` — bearer header parsing and validation
- Enforce auth on all routes except `/health`
- Stub `POST /mcp` — auth required, returns structured not-implemented
- Minimal token display in popover (copyable)

### Migration notes

- PR 2c `ServerService` gains Keychain token injection at server creation
- Server must restart when token rotates
- PR 2d may add auto-start on launch as a separate follow-up

---

## Data flow (end state after PR 2c)

```
User taps "Start Server"
  → ServerStore.startServer()
    → ServerService.start()
      → create_server(ServerConfig, AppleProviderBridge stub)
      → start_server(handle)
        → Rust binds 127.0.0.1:3020
        → GET /health available

curl http://127.0.0.1:3020/health
  → {"ok": true}
```

No auth gate until PR 2d.

---

## Error handling (cross-cutting)

| Layer | Rule |
|-------|------|
| Rust | Typed `CoreError`; never panic across UniFFI |
| Swift services | Map `CoreError` once in `ServerService` |
| UI | Show `lastError` in red, copyable; never silent failure on Start/Stop |

---

## Open items

None. Scope is fully defined for PR 2a, PR 2b, and PR 2c. PR 2d is intentionally deferred with preview only.
# SwiftUI Shell + Rust Core + Embedded MCP HTTP Server — Architecture & Bootstrap Guide

A reusable pattern for macOS apps: one long-running native app process, a thin SwiftUI shell for views and platform integration, a Rust core library linked into the app through UniFFI, and a Rust-owned embedded MCP/HTTP server started by the app. Use this guide to bootstrap new projects from scratch.

This document is generic. It does not describe any specific product domain, persistence layer, cloud sync, or protocol implementation.

---

## 1. Overview

### One-process model

```
┌─────────────────────────────────────────────────────────────────────┐
│  AppleBridge.app                                                   │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ SwiftUI Shell                                                 │  │
│  │ - App lifecycle, menu bar, settings, status UI                │  │
│  │ - @Observable stores (UI state only)                          │  │
│  │ - Permission prompts, launch at login, Keychain               │  │
│  │ - Thin provider adapters for Apple-only frameworks            │  │
│  └─────────────────────────────┬─────────────────────────────────┘  │
│                                │ UniFFI                            │
│  ┌─────────────────────────────▼─────────────────────────────────┐  │
│  │ Rust Core                                                     │  │
│  │ - MCP server, HTTP transport, auth, routing                   │  │
│  │ - Provider registry, schemas, config validation               │  │
│  │ - Logging, diagnostics, typed errors, tests                   │  │
│  └─────────────────────────────┬─────────────────────────────────┘  │
│                                │ callback_interface               │
│  ┌─────────────────────────────▼─────────────────────────────────┐  │
│  │ Swift Provider Bridge                                         │  │
│  │ - Dispatch by provider + operation                            │  │
│  │ - Call Apple frameworks through thin adapters                 │  │
│  └─────────────────────────────┬─────────────────────────────────┘  │
│                                │ native framework APIs            │
│  ┌─────────────────────────────▼─────────────────────────────────┐  │
│  │ Apple Frameworks                                              │  │
│  │ - EventKit, MapKit, Contacts, HealthKit, PhotoKit, ...        │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                  │ HTTP on localhost
                                  ▼
                        MCP client → http://127.0.0.1:<port>/mcp
```

### Request flow

```
MCP client
  → http://127.0.0.1:<port>/mcp
    → Rust embedded server
      → Rust provider registry/router
        → Swift provider adapter via UniFFI callback
          → Apple framework
```

### Responsibility split

| Layer | Owns | Does not own |
|-------|------|--------------|
| **SwiftUI shell** | UI, menu bar, app lifecycle, permission prompts, launch at login, Keychain access, Apple framework calls | MCP transport, routing, auth, business rules |
| **Swift services** | Startup/shutdown wiring, generated binding integration, error display mapping, provider status presentation | Core logic, server internals, request validation |
| **Swift providers** | Thin translation layer over Apple frameworks | Business logic, auth, cross-provider orchestration |
| **Rust core** | MCP server, HTTP transport, auth, config validation, routing, provider registry, schemas, diagnostics, logging, typed errors, tests | SwiftUI, AppKit, permission prompts, direct Apple API calls |

### Core rules for this template

- Swift owns UI, menu bar, app lifecycle, permission prompts, launch at login, and Apple framework calls.
- Rust owns MCP server, HTTP transport, auth, config validation, routing, provider registry, schemas, logging, diagnostics, typed errors, and tests.
- Swift providers are thin adapters over Apple frameworks.
- Apple frameworks remain the system of record.
- No business logic in Swift providers.
- No application-specific assumptions.
- No remote access by default.
- Bind to `127.0.0.1` by default.
- Bearer token auth for MCP HTTP.
- Token is stored in Keychain on the Swift side; Rust receives it at runtime.
- Use UniFFI proc-macro mode only. No UDL files.
- Generated Swift bindings are never edited manually.

### Explicit non-goals for this template

- Cross-machine remote access by default
- A standalone stdio MCP binary as the primary architecture
- Product-specific domain models
- Persistence implementation details beyond config/token boundaries
- Cloud sync, background daemons, or distributed coordination
- iOS / iPadOS targets

### Why this process model

The app, embedded server, and provider bridge share one runtime boundary: the macOS app process. That removes the primary friction of a separate MCP binary:

- No extra process to install, spawn, monitor, or version independently
- No stdio transport as the control plane
- No duplicated config/auth state between Swift and Rust
- Direct Rust-to-Swift provider callbacks without ad hoc IPC

The result is a clean split: Swift owns platform integration, Rust owns the server.

---

## 2. Repository layout

Target structure for a new project named `AppleBridge`:

```text
AppleBridge/
├── AppleBridge/
│   ├── AppleBridgeApp.swift
│   ├── Models/
│   ├── Services/
│   │   ├── apple_bridge_core.swift   # GENERATED — do not edit
│   │   ├── CoreService.swift
│   │   ├── ServerService.swift
│   │   └── KeychainService.swift
│   ├── Providers/
│   │   ├── EventKit/
│   │   ├── MapKit/
│   │   ├── Contacts/
│   │   ├── HealthKit/
│   │   └── PhotoKit/
│   └── Views/
├── AppleBridgeTests/
├── AppleBridgeCore/
├── rust/
│   ├── Cargo.toml
│   ├── rustfmt.toml
│   ├── build.rs
│   ├── build-macos.sh
│   ├── uniffi-bindgen.rs
│   └── apple_bridge_core/
│       └── src/
│           ├── lib.rs
│           ├── error.rs
│           ├── config.rs
│           ├── auth.rs
│           ├── server.rs
│           ├── mcp.rs
│           ├── providers.rs
│           ├── diagnostics.rs
│           └── logging.rs
├── justfile
└── docs/
    └── architecture-bootstrap-guide.md
```

### Generated vs hand-written

| Path | Edit? | Regenerate how |
|------|-------|----------------|
| `AppleBridgeCore/` | Never | `just build-rust` |
| `AppleBridge/Services/apple_bridge_core.swift` | Never | Copy from `AppleBridgeCore/Sources/` after build |
| `AppleBridge/Services/*Service.swift` | Yes | Hand-written wrappers |
| `AppleBridge/Providers/` | Yes | Thin adapters over Apple frameworks |
| `rust/apple_bridge_core/src/` | Yes | Source of truth for the embedded server and FFI API |

### Module boundaries

| Rust module | Responsibility |
|-------------|----------------|
| `lib.rs` | Public UniFFI surface and exports |
| `error.rs` | Typed errors exposed through UniFFI |
| `config.rs` | Config types and validation rules |
| `auth.rs` | Bearer token parsing and request auth |
| `server.rs` | Server lifecycle and `ServerHandle` |
| `mcp.rs` | MCP HTTP handlers, schemas, protocol glue |
| `providers.rs` | Provider registry, router, bridge request/response mapping |
| `diagnostics.rs` | Health/status models and service diagnostics |
| `logging.rs` | `tracing` initialization |

---

## 3. Bootstrap steps

### Prerequisites

- macOS 26+
- Xcode 26+
- Swift 6.0+ (project `SWIFT_VERSION` in `project.yml`)
- Rust 1.85+ (edition 2024)
- `just` (recommended task runner)

```sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
cargo install just
rustup target add aarch64-apple-darwin
```

### Step 1 — Create the Rust workspace

`rust/Cargo.toml`:

```toml
[workspace]
members = ["apple_bridge_core"]
resolver = "2"

[workspace.package]
edition = "2024"
rust-version = "1.85"
```

`rust/apple_bridge_core/Cargo.toml`:

```toml
[package]
name = "apple_bridge_core"
version = "0.1.0"
edition = "2024"
rust-version = "1.85"

[lib]
crate-type = ["lib", "staticlib"]
name = "apple_bridge_core"

[dependencies]
uniffi = { version = "0.31", features = ["cli"] }
thiserror = "2"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
tokio = { version = "1", features = ["rt-multi-thread", "macros", "sync", "net"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
axum = "0.8"
http = "1"

[build-dependencies]
uniffi = { version = "0.31", features = ["build"] }

[[bin]]
name = "uniffi-bindgen"
path = "../uniffi-bindgen.rs"

[profile.release]
lto = true
codegen-units = 1
opt-level = "z"
strip = true
```

`rust/rustfmt.toml`:

```toml
max_width = 120
tab_spaces = 2
```

`rust/build.rs`:

```rust
fn main() {
  // Proc-macro UniFFI mode: no UDL scaffolding generation.
}
```

`rust/uniffi-bindgen.rs`:

```rust
fn main() {
  uniffi::uniffi_bindgen_main()
}
```

### Step 2 — Define the Rust FFI surface

The app should start and stop the embedded server through a small exported API. Swift should not know the internals of the HTTP stack.

`rust/apple_bridge_core/src/lib.rs`:

```rust
mod auth;
mod config;
mod diagnostics;
mod error;
mod logging;
mod mcp;
mod providers;
mod server;

pub use config::{ProviderConfig, ProviderRequest, ProviderResponse, ServerConfig};
pub use diagnostics::ServerStatus;
pub use error::CoreError;
pub use providers::ProviderBridge;
pub use server::ServerHandle;

#[uniffi::export]
pub fn init_logging() {
  logging::init_logging();
}

#[uniffi::export]
pub fn create_server(
  config: ServerConfig,
  provider: Box<dyn ProviderBridge>,
) -> Result<std::sync::Arc<ServerHandle>, CoreError> {
  server::create_server(config, provider)
}

#[uniffi::export]
pub fn start_server(handle: std::sync::Arc<ServerHandle>) -> Result<(), CoreError> {
  handle.start()
}

#[uniffi::export]
pub fn stop_server(handle: std::sync::Arc<ServerHandle>) -> Result<(), CoreError> {
  handle.stop()
}

#[uniffi::export]
pub fn server_status(handle: std::sync::Arc<ServerHandle>) -> ServerStatus {
  handle.status()
}

uniffi::setup_scaffolding!();
```

#### UniFFI type cheat sheet

| Rust attribute | Use for |
|----------------|---------|
| `#[derive(uniffi::Record)]` | Structs passed by value |
| `#[derive(uniffi::Enum)]` | Simple enums |
| `#[derive(uniffi::Error)]` | Error enums with `thiserror` |
| `#[derive(uniffi::Object)]` | Stateful objects such as `ServerHandle` |
| `#[uniffi::export] impl` | Methods on UniFFI objects |
| `#[uniffi::export(callback_interface)]` | Swift callback interfaces implemented on the Swift side |
| `#[uniffi::export] pub fn` | Stateless exported functions |

Rules:

- Proc-macro mode only. No UDL files.
- Re-export the public FFI API from `lib.rs`.
- Never `unwrap()` / `expect()` on paths reachable from UniFFI. Panics abort the app.

### Step 3 — Add config, provider, and status records

The embedded server needs a concrete runtime configuration and a single callback entry point for platform providers.

`rust/apple_bridge_core/src/config.rs`:

```rust
#[derive(Debug, Clone, uniffi::Record)]
pub struct ProviderConfig {
  pub name: String,
  pub enabled: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ServerConfig {
  pub host: String,
  pub port: u16,
  pub bearer_token: String,
  pub enabled_providers: Vec<ProviderConfig>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ProviderRequest {
  pub provider: String,
  pub operation: String,
  pub payload_json: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ProviderResponse {
  pub ok: bool,
  pub payload_json: String,
  pub error_json: Option<String>,
}
```

`rust/apple_bridge_core/src/diagnostics.rs`:

```rust
#[derive(Debug, Clone, uniffi::Record)]
pub struct ProviderStatus {
  pub name: String,
  pub enabled: bool,
  pub healthy: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ServerStatus {
  pub running: bool,
  pub bound_host: String,
  pub bound_port: u16,
  pub provider_statuses: Vec<ProviderStatus>,
  pub last_error: Option<String>,
}
```

Validation guidance:

- Default host: `127.0.0.1`
- Default port: app-defined, but document one stable development default such as `3020`
- Field validation rules: see **§5 Config model → Validation matrix** (canonical contract for `validate_config()`)

### Step 4 — Define the provider callback interface

Swift implements the provider bridge; Rust owns routing and calls into Swift only when platform APIs are required.

`rust/apple_bridge_core/src/providers.rs`:

```rust
use crate::config::{ProviderRequest, ProviderResponse};

#[uniffi::export(callback_interface)]
pub trait ProviderBridge: Send + Sync {
  fn call_provider(&self, request: ProviderRequest) -> ProviderResponse;
}
```

Design rules:

- Rust selects the provider and operation.
- Swift receives a normalized request envelope.
- Swift returns serialized payload/error JSON.
- Swift providers should not interpret auth, config, or cross-provider policy.

### Step 5 — Implement `ServerHandle`

The embedded server should be represented as a stateful Rust object with explicit lifecycle methods. Swift gets a handle, starts it, reads status, and stops it.

`rust/apple_bridge_core/src/server.rs`:

```rust
use std::sync::{Arc, Mutex};

use crate::{
  config::ServerConfig,
  diagnostics::ServerStatus,
  error::CoreError,
  providers::ProviderBridge,
};

#[derive(uniffi::Object)]
pub struct ServerHandle {
  inner: Mutex<ServerInner>,
}

struct ServerInner {
  config: ServerConfig,
  provider: Arc<dyn ProviderBridge>,
  status: ServerStatus,
}

pub fn create_server(
  config: ServerConfig,
  provider: Box<dyn ProviderBridge>,
) -> Result<Arc<ServerHandle>, CoreError> {
  validate_config(&config)?;

  Ok(Arc::new(ServerHandle {
    inner: Mutex::new(ServerInner {
      status: ServerStatus {
        running: false,
        bound_host: config.host.clone(),
        bound_port: config.port,
        provider_statuses: Vec::new(),
        last_error: None,
      },
      config,
      provider: Arc::from(provider),
    }),
  }))
}

#[uniffi::export]
impl ServerHandle {
  pub fn start(&self) -> Result<(), CoreError> {
    // Bind listener, start runtime task, mark running.
    Ok(())
  }

  pub fn stop(&self) -> Result<(), CoreError> {
    // Trigger graceful shutdown and mark stopped.
    Ok(())
  }

  pub fn status(&self) -> ServerStatus {
    match self.inner.lock() {
      Ok(inner) => inner.status.clone(),
      Err(_) => ServerStatus {
        running: false,
        bound_host: String::new(),
        bound_port: 0,
        provider_statuses: Vec::new(),
        last_error: Some("server state unavailable".into()),
      },
    }
  }
}
```

Implementation guidance:

- `create_server()` validates config and constructs the runtime state, but does not bind the port.
- `start()` binds the listener and starts the long-running HTTP task.
- `stop()` performs graceful shutdown and releases the port.
- `status()` must be safe to call before start, while running, and after stop.
- If host/port/token/provider configuration changes, stop the old server and create a new handle rather than mutating a live one in place.

### Step 6 — Build macOS static library and generate Swift bindings

`rust/build-macos.sh`:

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/AppleBridgeCore"
XCFRAMEWORK_DIR="$OUTPUT_DIR/apple_bridge_core.xcframework"

cd "$SCRIPT_DIR"

ARM64_LIB="target/aarch64-apple-darwin/release/libapple_bridge_core.a"

echo "Building macOS arm64..."
cargo build --release -p apple_bridge_core --target aarch64-apple-darwin

mkdir -p "$OUTPUT_DIR/Sources"
mkdir -p "$OUTPUT_DIR/Headers"

MACOS_LIB_DIR="$OUTPUT_DIR/lib-macos-arm64"
mkdir -p "$MACOS_LIB_DIR"
cp "$ARM64_LIB" "$MACOS_LIB_DIR/libapple_bridge_core.a"

echo "Generating Swift bindings..."
cargo run --release -p apple_bridge_core --bin uniffi-bindgen generate \
  --library "$ARM64_LIB" \
  --language swift \
  --out-dir "$OUTPUT_DIR/Sources"

if [ -f "$OUTPUT_DIR/Sources/apple_bridge_coreFFI.h" ]; then
  mv "$OUTPUT_DIR/Sources/apple_bridge_coreFFI.h" "$OUTPUT_DIR/Headers/"
fi

cat > "$OUTPUT_DIR/Headers/module.modulemap" << 'EOF'
module apple_bridge_coreFFI {
    header "apple_bridge_coreFFI.h"
    export *
}
EOF

rm -rf "$XCFRAMEWORK_DIR"
xcodebuild -create-xcframework \
  -library "$MACOS_LIB_DIR/libapple_bridge_core.a" \
  -headers "$OUTPUT_DIR/Headers" \
  -output "$XCFRAMEWORK_DIR"

rm -rf "$MACOS_LIB_DIR" "$OUTPUT_DIR/Headers"

cp "$OUTPUT_DIR/Sources/apple_bridge_core.swift" \
  "$PROJECT_DIR/AppleBridge/Services/apple_bridge_core.swift"

echo "Done: $XCFRAMEWORK_DIR"
```

```sh
chmod +x rust/build-macos.sh
just build-rust
```

### Step 7 — Create the Xcode macOS app

1. Create a new macOS App project in Xcode with SwiftUI and Swift 6.
2. Add `AppleBridgeCore/apple_bridge_core.xcframework` to the app target.
3. Add `AppleBridge/Services/apple_bridge_core.swift` to the app target.
4. Enable strict concurrency checks.
5. Keep generated bindings separate from hand-written services.

Minimum file structure:

```text
AppleBridge/
  AppleBridgeApp.swift
  Models/AppStore.swift
  Models/ServerSettings.swift
  Services/CoreService.swift
  Services/ServerService.swift
  Services/KeychainService.swift
  Providers/EventKit/EventKitProvider.swift
  Providers/MapKit/MapKitProvider.swift
  Views/SettingsView.swift
```

### Step 8 — Swift startup and shutdown wiring

Swift owns the app lifecycle and should explicitly start and stop the Rust server.

`AppleBridge/Services/ServerService.swift`:

```swift
import Foundation

@MainActor
final class ServerService {
    private var handle: ServerHandle?
    private let keychain = KeychainService()
    private let providerBridge = AppleProviderBridge()

    func start(settings: ServerSettings) throws {
        initLogging()

        let token = try keychain.loadOrCreateBearerToken()
        let config = ServerConfig(
            host: settings.host,
            port: settings.port,
            bearerToken: token,
            enabledProviders: settings.enabledProviders.map {
                ProviderConfig(name: $0.name, enabled: $0.enabled)
            }
        )

        let handle = try createServer(config: config, provider: providerBridge)
        try startServer(handle: handle)
        self.handle = handle
    }

    func stop() throws {
        guard let handle else { return }
        try stopServer(handle: handle)
        self.handle = nil
    }

    func status() -> ServerStatus? {
        guard let handle else { return nil }
        return serverStatus(handle: handle)
    }
}
```

`AppleBridge/AppleBridgeApp.swift`:

```swift
import SwiftUI

@main
struct AppleBridgeApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task {
                    await store.startServerIfNeeded()
                }
        }
    }
}
```

Lifecycle rules:

- Start the Rust server during app startup after config/token resolution.
- Stop the Rust server during orderly app shutdown.
- Restart the Rust server when host or port changes.
- Recreate the server handle when bearer token or enabled providers change.
- Surface startup failure as a user-visible error message in SwiftUI.

### Step 9 — Keychain token handling

Swift should own secure storage. Rust receives the bearer token only at runtime through `ServerConfig`.

`AppleBridge/Services/KeychainService.swift`:

```swift
import Foundation
import Security

struct KeychainService {
    func loadOrCreateBearerToken() throws -> String {
        if let existing = try loadBearerToken() {
            return existing
        }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        try saveBearerToken(token)
        return token
    }

    private func loadBearerToken() throws -> String? {
        // Query the Keychain item for this app and return nil if it does not exist yet.
        return nil
    }

    private func saveBearerToken(_ token: String) throws {
        // Insert or update the Keychain item used for local MCP auth.
    }
}
```

Rules:

- The token is never hard-coded into the Rust library.
- The token is never stored in generated Swift bindings.
- Rust validates the token but does not persist it by default.
- Rotating the token requires a server restart with a new `ServerConfig`.

### Step 10 — Provider bridge implementation in Swift

Swift implements a single bridge and dispatches to provider modules by name.

`AppleBridge/Providers/AppleProviderBridge.swift`:

```swift
import Foundation

final class AppleProviderBridge: ProviderBridge {
    func callProvider(request: ProviderRequest) -> ProviderResponse {
        switch request.provider {
        case "eventkit":
            return EventKitProvider.shared.handle(request)
        case "mapkit":
            return MapKitProvider.shared.handle(request)
        default:
            return ProviderResponse(
                ok: false,
                payloadJson: "{}",
                errorJson: #"{"code":"unknown_provider"}"#
            )
        }
    }
}
```

Rules:

- Provider dispatch lives in one bridge type.
- Providers should be thin wrappers over Apple frameworks.
- Providers may deserialize `payload_json` into Apple-specific request types, call the framework, then serialize the response.
- Providers should not own routing, auth, or config validation.
- Unknown providers should return structured errors, not crash.

### Step 11 — Provider module pattern for Apple APIs

Each Apple framework gets its own small module with one clear purpose.

Example layout:

```text
AppleBridge/Providers/
  EventKit/
    EventKitProvider.swift
    EventKitModels.swift
  Contacts/
    ContactsProvider.swift
  MapKit/
    MapKitProvider.swift
```

Example provider:

```swift
import Foundation
import EventKit

final class EventKitProvider {
    static let shared = EventKitProvider()

    private let store = EKEventStore()

    func handle(_ request: ProviderRequest) -> ProviderResponse {
        switch request.operation {
        case "list_calendars":
            return listCalendars()
        default:
            return ProviderResponse(
                ok: false,
                payloadJson: "{}",
                errorJson: #"{"code":"unknown_operation"}"#
            )
        }
    }

    private func listCalendars() -> ProviderResponse {
        let calendars = store.calendars(for: .event).map { ["title": $0.title] }
        let data = try? JSONSerialization.data(withJSONObject: calendars)
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return ProviderResponse(ok: true, payloadJson: json, errorJson: nil)
    }
}
```

Provider rules:

- Keep modules small and framework-specific.
- Centralize permission prompts in Swift-owned app services, not buried in provider logic when possible.
- Treat Apple frameworks as the system of record.
- Do not copy domain logic from Rust into providers.

---

## 4. Embedded server architecture

### Startup sequence

```
App launch
  → Swift loads settings
  → Swift loads or creates bearer token in Keychain
  → Swift constructs ServerConfig
  → Swift creates AppleProviderBridge
  → Swift calls create_server(...)
  → Swift calls start_server(...)
  → Rust binds 127.0.0.1:<port> and starts HTTP server
```

### Shutdown sequence

```
App termination or server disable
  → Swift calls stop_server(...)
  → Rust begins graceful shutdown
  → Listener closes
  → In-flight requests drain or time out
  → Port is released
```

### Restart behavior

Recreate the server handle when any of these change:

- Host
- Port
- Bearer token
- Enabled providers

Do not attempt to hot-edit a live server object in place unless you have a concrete need and tests for reconfiguration semantics. For a bootstrap template, stop and recreate is simpler and more predictable.

### Server lifecycle ownership

- Swift decides when the server should exist.
- Rust decides how the server runs internally once started.
- Swift may poll `server_status()` for settings/status UI.
- Rust should expose enough diagnostics for UI and logs, but not UI-specific presentation logic.

---

## 5. Config model

Use one explicit runtime config record passed from Swift to Rust.

### Required fields

| Field | Type | Owner | Notes |
|-------|------|-------|-------|
| `host` | `String` | Swift settings UI | Default `127.0.0.1` |
| `port` | `u16` | Swift settings UI | Default example `3020` |
| `bearer_token` | `String` | Swift Keychain | Non-empty, runtime only |
| `enabled_providers` | `[ProviderConfig]` | Swift settings UI | Drives provider availability |

### Validation matrix

Canonical contract for `validate_config()` in `rust/apple_bridge_core/src/config.rs`. PR specs implement rows by PR column; naming philosophy for provider IDs lives in `docs/conventions.md` § Providers and operations.

| Field | Rule | Error message | PR |
|-------|------|---------------|-----|
| `host` | Non-blank after trim | `host must not be blank` | 2a |
| `host` | Loopback allowlist: `127.0.0.1`, `localhost`, `::1` | `host must be loopback` | 2a |
| `port` | `> 0` | `port must not be 0` | 2a |
| `enabled_providers[].name` | Non-blank after trim | `provider name must not be blank` | 2a |
| `enabled_providers[].name` | Lowercase, no whitespace | `invalid provider name: {name}` | 2a |
| `enabled_providers[].name` | Unique after trim | `duplicate provider name: {name}` | 2a |
| `bearer_token` | Non-empty | `bearer token must not be empty` | 2d |
| `enabled_providers` | At least one enabled (if app requires) | TBD | later |

Notes:

- Validation runs at `create_server()`, not lazily on first request.
- `ProviderRequest.provider` / `.operation` shape checks are request-time (PR 2b+ routing), not config-time.

### Recommended defaults

```text
host = "127.0.0.1"
port = 3020
enabled_providers = app-defined
```

Store user preferences on the Swift side. Treat Rust as the validation and execution engine, not the source of persisted UI settings.

---

## 6. Auth model

### Transport default

Use HTTP on localhost as the primary MCP transport:

```text
http://127.0.0.1:<port>/mcp
```

### Bearer token handling

- Swift stores the token in Keychain.
- Swift injects the token into `ServerConfig` at startup.
- Rust enforces bearer token auth on authenticated endpoints.
- Requests without `Authorization: Bearer <token>` should fail with an auth error.

### Auth responsibilities

| Concern | Owner |
|---------|-------|
| Secure token storage | Swift |
| Header parsing | Rust |
| Token comparison | Rust |
| Unauthorized response shape | Rust |
| Token rotation UI | Swift |

### Security defaults

- Bind to `127.0.0.1` by default
- No remote access by default
- Do not silently fall back to unauthenticated MCP
- Do not log bearer tokens
- Treat all client input as untrusted

---

## 7. MCP HTTP endpoints

The embedded Rust server should expose a small set of operational endpoints.

### Required endpoints

| Path | Purpose |
|------|---------|
| `/mcp` | MCP HTTP endpoint |
| `/health` | Lightweight health check |
| `/status` | Optional structured status payload for diagnostics |

### Health endpoint behavior

`/health` should be cheap and safe to call repeatedly. It should answer whether the server is alive and listening. It does not need to expose auth-sensitive details.

Minimal example response:

```json
{
  "ok": true
}
```

### Status endpoint behavior

`/status` can expose:

- bound host and port
- running/stopped state
- provider enabled/healthy state
- last startup or runtime error

Keep the response operational, not product-specific.

---

## 8. Integration patterns reference

### Swift starts Rust

```text
App lifecycle → ServerService → generated UniFFI API → Rust ServerHandle
```

- Initialize logging once at startup.
- Load token from Keychain before creating the server.
- Recreate the server on config changes that affect transport or auth.

### Rust calls Swift

```text
HTTP request → Rust route → provider registry → ProviderBridge callback
  → Swift provider adapter → Apple framework
```

- Rust chooses which provider to invoke.
- Swift performs only framework-specific work.
- Swift returns structured JSON payloads or errors.

### Error propagation

```text
Rust CoreError (thiserror + uniffi::Error)
  → generated Swift CoreError
    → hand-written AppError
      → SwiftUI Text with .textSelection(.enabled)
```

Never discard the Rust error class at the Swift boundary. Translate it once, centrally.

### Changing the FFI API

1. Edit Rust types/functions in `apple_bridge_core`
2. `just lint-rust && TZ=UTC just test-rust`
3. `just build-rust`
4. Fix Swift call sites in hand-written services
5. Never patch `apple_bridge_core.swift` manually

---

## 9. Rust best practices

> **Canonical reference:** `docs/conventions.md` — naming, libraries, formatting, errors, concurrency, and testing. This section summarizes patterns used in the bootstrap template.

### Toolchain and style

| Rule | Value |
|------|-------|
| Edition | 2024 |
| MSRV | 1.85 |
| UniFFI | 0.31 |
| Formatting | `rustfmt.toml`: 120 cols, 2-space indent |
| Lint | `cargo clippy -- -D warnings` |
| File size | ~150 lines per module; split by responsibility |

### Errors

- Use `thiserror` for error enums.
- Add `#[derive(uniffi::Error)]` for FFI-exposed errors.
- Return `Result<T, CoreError>` on all user-input paths.
- Classify errors precisely before generic fallback buckets.
- Never `unwrap()` / `expect()` on user input or external data paths.

### Logging

- Use `tracing` in Rust.
- Export `init_logging()` and call it from Swift startup.
- Disable ANSI in FFI contexts.
- Include server lifecycle and auth failure events in logs.

### Config and input validation

- Validate all config before server start.
- Validate request payload sizes before parsing.
- Validate provider names and operations before callback dispatch.
- Keep auth and config validation in Rust, not in Swift providers.

### Async and runtimes

- A long-running server should own its Tokio runtime or runtime handle explicitly.
- `start()` should fail cleanly if the port cannot be bound.
- `stop()` should support graceful shutdown.
- Prefer explicit shutdown signaling over dropping tasks and hoping the runtime unwinds cleanly.

### Testing

- Unit tests: `#[cfg(test)]` in-module
- Integration tests: `tests/` directory
- Use mock provider bridges for server tests
- Run tests with `TZ=UTC`

---

## 10. Swift best practices

### Concurrency

- Use Swift 6 strict concurrency rules.
- Use `@Observable` for UI stores.
- Mark UI-driving stores `@MainActor`.
- Use `@concurrent` when wrapping blocking FFI calls that should not run on the main actor.
- Avoid `Task.detached` unless you have a concrete isolation reason.

### Generated bindings

- Treat generated `apple_bridge_core.swift` as read-only.
- Add hand-written wrappers in `Services/`.
- Do not mix generated and hand-written code in one file.

### Error presentation

- Convert generated Rust errors into app-level Swift errors in one place.
- Surface operational errors in SwiftUI with text selection enabled.
- Keep user-visible server errors copyable for debugging.

Example:

```swift
Text(error.message)
    .foregroundStyle(.red)
    .textSelection(.enabled)
```

### Provider adapters

- Keep providers thin.
- Prefer one provider module per Apple framework.
- Put permissions, settings, and lifecycle orchestration in Swift app services rather than scattering them across providers.

---

## 11. Testing strategy

### Rust unit tests

Test validation, auth, routing, and provider dispatch in Rust.

Example:

```rust
#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn rejects_empty_token() {
    let config = ServerConfig {
      host: "127.0.0.1".into(),
      port: 3020,
      bearer_token: "".into(),
      enabled_providers: vec![],
    };

    assert!(create_server(config, Box::new(MockProviderBridge)).is_err());
  }
}
```

### Mock provider bridge

The main embedded-server test seam is a fake `ProviderBridge`.

Example:

```rust
struct MockProviderBridge;

impl ProviderBridge for MockProviderBridge {
  fn call_provider(&self, request: ProviderRequest) -> ProviderResponse {
    ProviderResponse {
      ok: true,
      payload_json: format!(r#"{{"provider":"{}","operation":"{}"}}"#, request.provider, request.operation),
      error_json: None,
    }
  }
}
```

Use it to test:

- provider dispatch
- auth enforcement
- unknown provider handling
- server lifecycle behavior

### Swift tests

Create a `AppleBridgeTests` target and test the hand-written Swift services.

Example:

```swift
import Testing
@testable import AppleBridge

@Suite("ServerService")
struct ServerServiceTests {
    @Test("status is nil before start")
    @MainActor
    func statusBeforeStart() {
        let service = ServerService()
        #expect(service.status() == nil)
    }
}
```

### UTC guidance

Set `TZ=UTC` for deterministic timestamp assertions in Rust and Swift test commands.

---

## 12. Smoke testing the embedded server

### Health check

Once the app has started the server on port `3020`, verify the listener:

```sh
curl http://127.0.0.1:3020/health
```

Expected result: a successful health response such as `{"ok":true}`.

### Authenticated MCP request expectations

MCP requests should require a bearer token header.

Example:

```sh
curl http://127.0.0.1:3020/mcp \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
```

Expected behavior:

- Valid token: request reaches the MCP handler
- Missing or invalid token: auth error response
- Disabled or unknown provider: structured provider error, not a crash

### Local HTTP MCP configuration notes

Development clients should be configured against a local HTTP URL, not a spawned binary. The exact MCP client config format varies, but the stable facts are:

- endpoint points at `http://127.0.0.1:<port>/mcp`
- auth uses a bearer token
- the macOS app must be running before the client connects

This template intentionally does not make Cursor, Claude Desktop, or other client-specific config snippets the primary usage model, because the architecture is app-hosted rather than tool-spawned.

---

## 13. justfile

`justfile`:

```just
# Build Rust core + XCFramework + Swift bindings (macOS)
build-rust:
    cd rust && ./build-macos.sh

test-rust:
    cd rust && TZ=UTC cargo test

lint-rust:
    cd rust && cargo clippy -- -D warnings

test-swift:
    TZ=UTC xcodebuild test -project AppleBridge.xcodeproj -scheme AppleBridge \
        -only-testing:AppleBridgeTests -destination 'platform=macOS' -quiet

test-all: test-rust test-swift

clean-rust:
    cd rust && cargo clean
    rm -rf AppleBridgeCore

rebuild: clean-rust build-rust
```

---

## 14. New app checklist

Copy this when spinning up a project from the template:

- [ ] Create Xcode macOS SwiftUI app target
- [ ] Create Rust workspace with one `apple_bridge_core` crate
- [ ] Add `error.rs`, `config.rs`, `auth.rs`, `server.rs`, `providers.rs`, `diagnostics.rs`, `logging.rs`
- [ ] Export the Rust server lifecycle through UniFFI
- [ ] Add `build-macos.sh` and `justfile`
- [ ] Run `just build-rust`; link XCFramework in Xcode
- [ ] Copy generated `apple_bridge_core.swift` into `AppleBridge/Services/`
- [ ] Add `ServerService.swift` and `KeychainService.swift`
- [ ] Add `AppleProviderBridge.swift`
- [ ] Add at least one provider module under `Providers/`
- [ ] Add status UI for server and providers
- [ ] Verify `curl http://127.0.0.1:3020/health`
- [ ] Verify authenticated MCP initialization over HTTP
- [ ] Add Rust tests with a mock provider bridge
- [ ] Add Swift tests for hand-written services

---

## 15. What to add per app

This template deliberately stops early. Each new app adds its own:

| Concern | Where it usually lives |
|---------|------------------------|
| Settings persistence | Swift settings models + storage service |
| Apple framework permissions | Swift services and providers |
| Domain-specific request/response schemas | Rust `mcp.rs` and `providers.rs` |
| Business logic | Rust `apple_bridge_core/src/` |
| Provider-specific Apple integration | `AppleBridge/Providers/` |
| Status and diagnostics UI | SwiftUI views + `server_status()` polling |

Keep the shell thin. Put server logic in Rust. Add Swift only where the platform requires it.

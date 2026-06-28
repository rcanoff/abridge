# PR 2a: Rust Skeleton + UniFFI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `apple_bridge_core` Rust crate with UniFFI server lifecycle API and `ProviderBridge` callback — state machine only, no HTTP, no Swift changes.

**Architecture:** Full module skeleton per architecture guide; `ServerHandle::start()`/`stop()` flip `running` without binding a port. Config has no `bearer_token` until PR 2d. Tests use `MockProviderBridge` as the primary seam.

**Tech Stack:** Rust 2024 / MSRV 1.85, UniFFI 0.31 proc-macro, thiserror 2, tracing, tokio/axum listed in Cargo.toml for PR 2b but unused in PR 2a code.

**Spec:** `docs/superpowers/specs/2026-06-27-pr2-mcp-server-design.md` (PR 2a section)  
**Branch:** `feat/pr2a-rust-uniffi-skeleton`  
**Conventions:** `docs/conventions.md`, `rust/AGENTS.md`

---

## File Map

| File | Responsibility |
|------|----------------|
| `rust/Cargo.toml` | Workspace root |
| `rust/rustfmt.toml` | Formatting (120 cols, 2 spaces) |
| `rust/build.rs` | Empty proc-macro UniFFI build script |
| `rust/uniffi-bindgen.rs` | Bindgen binary entry (for PR 2c) |
| `rust/apple_bridge_core/Cargo.toml` | Crate manifest + approved deps |
| `rust/apple_bridge_core/src/lib.rs` | UniFFI exports, module wiring |
| `rust/apple_bridge_core/src/error.rs` | `CoreError` |
| `rust/apple_bridge_core/src/config.rs` | Config records + `validate_config` |
| `rust/apple_bridge_core/src/diagnostics.rs` | `ServerStatus`, `ProviderStatus` |
| `rust/apple_bridge_core/src/logging.rs` | `init_logging` |
| `rust/apple_bridge_core/src/providers.rs` | `ProviderBridge` trait |
| `rust/apple_bridge_core/src/server.rs` | `ServerHandle` stub lifecycle |
| `rust/apple_bridge_core/tests/support/mock_provider.rs` | `MockProviderBridge` |
| `rust/apple_bridge_core/tests/config_validation.rs` | Config validation integration tests |
| `rust/apple_bridge_core/tests/server_lifecycle.rs` | Lifecycle + mock provider tests |

`justfile` already exists on `main` with `test-rust` / `lint-rust` — no change unless recipes fail.

---

### Task 1: Rust workspace bootstrap

**Files:**
- Create: `rust/Cargo.toml`
- Create: `rust/rustfmt.toml`
- Create: `rust/build.rs`
- Create: `rust/uniffi-bindgen.rs`
- Create: `rust/apple_bridge_core/Cargo.toml`
- Create: `rust/apple_bridge_core/src/lib.rs` (minimal stub)

- [ ] **Step 1: Create workspace `rust/Cargo.toml`**

```toml
[workspace]
members = ["apple_bridge_core"]
resolver = "2"

[workspace.package]
edition = "2024"
rust-version = "1.85"
```

- [ ] **Step 2: Create `rust/apple_bridge_core/Cargo.toml`**

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

- [ ] **Step 3: Create tooling files**

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

`rust/apple_bridge_core/src/lib.rs` (stub):

```rust
uniffi::setup_scaffolding!();
```

- [ ] **Step 4: Verify workspace compiles**

Run:
```bash
cd /Users/rcanoff/Projects/apple-bridge/rust
cargo build
```
Expected: `Finished` with no errors.

- [ ] **Step 5: Commit**

```bash
git add rust/
git commit -m "chore: bootstrap rust workspace for apple_bridge_core"
```

---

### Task 2: CoreError (TDD)

**Files:**
- Create: `rust/apple_bridge_core/src/error.rs`
- Modify: `rust/apple_bridge_core/src/lib.rs`
- Create: `rust/apple_bridge_core/tests/error_display.rs`

- [ ] **Step 1: Write failing test**

Create `rust/apple_bridge_core/tests/error_display.rs`:

```rust
use apple_bridge_core::CoreError;

#[test]
fn invalid_config_display() {
  let err = CoreError::InvalidConfig {
    message: "port must not be 0".into(),
  };
  assert_eq!(
    err.to_string(),
    "invalid configuration: port must not be 0"
  );
}
```

Add to `lib.rs`:

```rust
mod error;
pub use error::CoreError;
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /Users/rcanoff/Projects/apple-bridge
just test-rust
```
Expected: FAIL — `CoreError` not found or `to_string` missing

- [ ] **Step 3: Implement `error.rs`**

```rust
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum CoreError {
  #[error("invalid configuration: {message}")]
  InvalidConfig { message: String },

  #[error("server is already running")]
  AlreadyRunning,

  #[error("server state unavailable")]
  StateUnavailable,
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just test-rust`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/apple_bridge_core/src/error.rs rust/apple_bridge_core/src/lib.rs rust/apple_bridge_core/tests/error_display.rs
git commit -m "feat: add CoreError for UniFFI"
```

---

### Task 3: Config types and validation (TDD)

**Files:**
- Create: `rust/apple_bridge_core/src/config.rs`
- Modify: `rust/apple_bridge_core/src/lib.rs`
- Create: `rust/apple_bridge_core/tests/config_validation.rs`

- [ ] **Step 1: Write failing tests**

Create `rust/apple_bridge_core/tests/config_validation.rs`:

```rust
use apple_bridge_core::{CoreError, ProviderConfig, ServerConfig, validate_config};

fn sample_config() -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port: 3020,
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
  }
}

#[test]
fn accepts_loopback_config() {
  assert!(validate_config(&sample_config()).is_ok());
}

#[test]
fn rejects_blank_host() {
  let mut config = sample_config();
  config.host = "  ".into();
  assert!(matches!(
    validate_config(&config),
    Err(CoreError::InvalidConfig { .. })
  ));
}

#[test]
fn rejects_wildcard_host() {
  let mut config = sample_config();
  config.host = "0.0.0.0".into();
  assert!(matches!(
    validate_config(&config),
    Err(CoreError::InvalidConfig { .. })
  ));
}

#[test]
fn rejects_port_zero() {
  let mut config = sample_config();
  config.port = 0;
  assert!(matches!(
    validate_config(&config),
    Err(CoreError::InvalidConfig { .. })
  ));
}

#[test]
fn rejects_duplicate_provider_names() {
  let mut config = sample_config();
  config.enabled_providers.push(ProviderConfig {
    name: "eventkit".into(),
    enabled: false,
  });
  assert!(matches!(
    validate_config(&config),
    Err(CoreError::InvalidConfig { .. })
  ));
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test-rust`  
Expected: FAIL — types / `validate_config` not found

- [ ] **Step 3: Implement `config.rs`**

```rust
use crate::error::CoreError;

#[derive(Debug, Clone, uniffi::Record)]
pub struct ProviderConfig {
  pub name: String,
  pub enabled: bool,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ServerConfig {
  pub host: String,
  pub port: u16,
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

pub fn validate_config(config: &ServerConfig) -> Result<(), CoreError> {
  let host = config.host.trim();
  if host.is_empty() {
    return Err(CoreError::InvalidConfig {
      message: "host must not be blank".into(),
    });
  }

  if host == "0.0.0.0" || host == "::" {
    return Err(CoreError::InvalidConfig {
      message: "host must be loopback".into(),
    });
  }

  if config.port == 0 {
    return Err(CoreError::InvalidConfig {
      message: "port must not be 0".into(),
    });
  }

  let mut seen = std::collections::HashSet::new();
  for provider in &config.enabled_providers {
    let name = provider.name.trim();
    if name.is_empty() {
      return Err(CoreError::InvalidConfig {
        message: "provider name must not be blank".into(),
      });
    }
    if !seen.insert(name.to_string()) {
      return Err(CoreError::InvalidConfig {
        message: format!("duplicate provider name: {name}"),
      });
    }
  }

  Ok(())
}
```

Update `lib.rs`:

```rust
mod config;
mod error;

pub use config::{
  ProviderConfig, ProviderRequest, ProviderResponse, ServerConfig, validate_config,
};
pub use error::CoreError;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test-rust`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/apple_bridge_core/src/config.rs rust/apple_bridge_core/src/lib.rs rust/apple_bridge_core/tests/config_validation.rs
git commit -m "feat: add server config types and validation"
```

---

### Task 4: Diagnostics and logging

**Files:**
- Create: `rust/apple_bridge_core/src/diagnostics.rs`
- Create: `rust/apple_bridge_core/src/logging.rs`
- Modify: `rust/apple_bridge_core/src/lib.rs`

- [ ] **Step 1: Implement `diagnostics.rs`**

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

- [ ] **Step 2: Implement `logging.rs`**

```rust
use std::sync::Once;

static INIT: Once = Once::new();

pub fn init_logging() {
  INIT.call_once(|| {
    tracing_subscriber::fmt()
      .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
      .with_ansi(false)
      .init();
  });
}
```

- [ ] **Step 3: Wire `lib.rs`**

```rust
mod config;
mod diagnostics;
mod error;
mod logging;

pub use config::{
  ProviderConfig, ProviderRequest, ProviderResponse, ServerConfig, validate_config,
};
pub use diagnostics::{ProviderStatus, ServerStatus};
pub use error::CoreError;

#[uniffi::export]
pub fn init_logging() {
  logging::init_logging();
}

uniffi::setup_scaffolding!();
```

- [ ] **Step 4: Build**

Run: `cargo build` in `rust/`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/apple_bridge_core/src/diagnostics.rs rust/apple_bridge_core/src/logging.rs rust/apple_bridge_core/src/lib.rs
git commit -m "feat: add diagnostics types and logging init"
```

---

### Task 5: ProviderBridge + MockProviderBridge

**Files:**
- Create: `rust/apple_bridge_core/src/providers.rs`
- Create: `rust/apple_bridge_core/tests/support/mock_provider.rs`
- Create: `rust/apple_bridge_core/tests/provider_bridge.rs`
- Modify: `rust/apple_bridge_core/src/lib.rs`

- [ ] **Step 1: Write failing test**

Create `rust/apple_bridge_core/tests/support/mock_provider.rs`:

```rust
use apple_bridge_core::{ProviderBridge, ProviderRequest, ProviderResponse};
use std::sync::{Arc, Mutex};

pub struct MockProviderBridge {
  pub last_request: Arc<Mutex<Option<ProviderRequest>>>,
}

impl MockProviderBridge {
  pub fn new() -> Self {
    Self {
      last_request: Arc::new(Mutex::new(None)),
    }
  }
}

impl ProviderBridge for MockProviderBridge {
  fn call_provider(&self, request: ProviderRequest) -> ProviderResponse {
    *self.last_request.lock().expect("mock lock") = Some(request.clone());
    ProviderResponse {
      ok: true,
      payload_json: r#"{"mock":true}"#.into(),
      error_json: None,
    }
  }
}
```

Create `rust/apple_bridge_core/tests/provider_bridge.rs`:

```rust
mod support;

use apple_bridge_core::{ProviderBridge, ProviderRequest};
use support::mock_provider::MockProviderBridge;

#[test]
fn mock_provider_records_request() {
  let mock = MockProviderBridge::new();
  let response = mock.call_provider(ProviderRequest {
    provider: "eventkit".into(),
    operation: "list_calendars".into(),
    payload_json: "{}".into(),
  });

  assert!(response.ok);
  let recorded = mock.last_request.lock().expect("mock lock").clone().expect("request");
  assert_eq!(recorded.provider, "eventkit");
  assert_eq!(recorded.operation, "list_calendars");
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-rust`  
Expected: FAIL — `ProviderBridge` not found

- [ ] **Step 3: Implement `providers.rs`**

```rust
use crate::config::{ProviderRequest, ProviderResponse};

#[uniffi::export(callback_interface)]
pub trait ProviderBridge: Send + Sync {
  fn call_provider(&self, request: ProviderRequest) -> ProviderResponse;
}
```

Update `lib.rs`:

```rust
mod providers;
pub use providers::ProviderBridge;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `just test-rust`  
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/apple_bridge_core/src/providers.rs rust/apple_bridge_core/src/lib.rs rust/apple_bridge_core/tests/
git commit -m "feat: add ProviderBridge callback interface and mock"
```

---

### Task 6: ServerHandle stub lifecycle (TDD)

**Files:**
- Create: `rust/apple_bridge_core/src/server.rs`
- Create: `rust/apple_bridge_core/tests/server_lifecycle.rs`
- Modify: `rust/apple_bridge_core/src/lib.rs`

- [ ] **Step 1: Write failing tests**

Create `rust/apple_bridge_core/tests/server_lifecycle.rs`:

```rust
mod support;

use apple_bridge_core::{
  create_server, start_server, stop_server, server_status, ProviderConfig, ServerConfig,
};
use support::mock_provider::MockProviderBridge;

fn sample_config() -> ServerConfig {
  ServerConfig {
    host: "127.0.0.1".into(),
    port: 3020,
    enabled_providers: vec![ProviderConfig {
      name: "eventkit".into(),
      enabled: true,
    }],
  }
}

#[test]
fn lifecycle_start_stop() {
  let handle = create_server(sample_config(), Box::new(MockProviderBridge::new()))
    .expect("create_server");

  let before = server_status(handle.clone());
  assert!(!before.running);

  start_server(handle.clone()).expect("start");
  let running = server_status(handle.clone());
  assert!(running.running);
  assert_eq!(running.bound_host, "127.0.0.1");
  assert_eq!(running.bound_port, 3020);
  assert_eq!(running.provider_statuses.len(), 1);

  stop_server(handle.clone()).expect("stop");
  let stopped = server_status(handle);
  assert!(!stopped.running);
}

#[test]
fn start_twice_returns_already_running() {
  let handle = create_server(sample_config(), Box::new(MockProviderBridge::new()))
    .expect("create_server");
  start_server(handle.clone()).expect("first start");
  let err = start_server(handle).expect_err("second start");
  assert_eq!(err.to_string(), "server is already running");
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test-rust`  
Expected: FAIL — `create_server` not found

- [ ] **Step 3: Implement `server.rs`**

```rust
use std::sync::{Arc, Mutex};

use crate::{
  config::{validate_config, ServerConfig},
  diagnostics::{ProviderStatus, ServerStatus},
  error::CoreError,
  providers::ProviderBridge,
};

#[derive(uniffi::Object)]
pub struct ServerHandle {
  inner: Mutex<ServerInner>,
}

struct ServerInner {
  config: ServerConfig,
  #[allow(dead_code)]
  provider: Arc<dyn ProviderBridge>,
  status: ServerStatus,
}

fn initial_status(config: &ServerConfig) -> ServerStatus {
  ServerStatus {
    running: false,
    bound_host: config.host.clone(),
    bound_port: config.port,
    provider_statuses: config
      .enabled_providers
      .iter()
      .map(|p| ProviderStatus {
        name: p.name.clone(),
        enabled: p.enabled,
        healthy: false,
      })
      .collect(),
    last_error: None,
  }
}

fn running_status(config: &ServerConfig) -> ServerStatus {
  ServerStatus {
    running: true,
    bound_host: config.host.clone(),
    bound_port: config.port,
    provider_statuses: config
      .enabled_providers
      .iter()
      .map(|p| ProviderStatus {
        name: p.name.clone(),
        enabled: p.enabled,
        healthy: p.enabled,
      })
      .collect(),
    last_error: None,
  }
}

pub fn create_server(
  config: ServerConfig,
  provider: Box<dyn ProviderBridge>,
) -> Result<Arc<ServerHandle>, CoreError> {
  validate_config(&config)?;

  Ok(Arc::new(ServerHandle {
    inner: Mutex::new(ServerInner {
      status: initial_status(&config),
      config,
      provider: Arc::from(provider),
    }),
  }))
}

#[uniffi::export]
impl ServerHandle {
  pub fn start(&self) -> Result<(), CoreError> {
    let mut inner = self
      .inner
      .lock()
      .map_err(|_| CoreError::StateUnavailable)?;

    if inner.status.running {
      return Err(CoreError::AlreadyRunning);
    }

    inner.status = running_status(&inner.config);
    Ok(())
  }

  pub fn stop(&self) -> Result<(), CoreError> {
    let mut inner = self
      .inner
      .lock()
      .map_err(|_| CoreError::StateUnavailable)?;

    inner.status = initial_status(&inner.config);
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

- [ ] **Step 4: Complete `lib.rs` exports**

```rust
mod config;
mod diagnostics;
mod error;
mod logging;
mod providers;
mod server;

pub use config::{
  ProviderConfig, ProviderRequest, ProviderResponse, ServerConfig, validate_config,
};
pub use diagnostics::{ProviderStatus, ServerStatus};
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
) -> Result<Arc<ServerHandle>, CoreError> {
  server::create_server(config, provider)
}

#[uniffi::export]
pub fn start_server(handle: Arc<ServerHandle>) -> Result<(), CoreError> {
  handle.start()
}

#[uniffi::export]
pub fn stop_server(handle: Arc<ServerHandle>) -> Result<(), CoreError> {
  handle.stop()
}

#[uniffi::export]
pub fn server_status(handle: Arc<ServerHandle>) -> ServerStatus {
  handle.status()
}

uniffi::setup_scaffolding!();
```

Add `use std::sync::Arc;` at top of `lib.rs`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `just test-rust`  
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add rust/apple_bridge_core/src/server.rs rust/apple_bridge_core/src/lib.rs rust/apple_bridge_core/tests/server_lifecycle.rs
git commit -m "feat: add ServerHandle stub lifecycle and UniFFI exports"
```

---

### Task 7: Lint and PR verification

**Files:** none (verification only)

- [ ] **Step 1: Run full Rust verification**

```bash
cd /Users/rcanoff/Projects/apple-bridge
just lint-rust
TZ=UTC just test-rust
```

Expected: clippy clean, all tests pass.

- [ ] **Step 2: Confirm no Swift changes**

```bash
git diff main --name-only | grep -E '^AppleBridge' || echo "No Swift changes"
```

Expected: `No Swift changes`

- [ ] **Step 3: PR checklist**

- [ ] `just lint-rust && just test-rust` pass
- [ ] No `auth.rs`, `mcp.rs`, `build-macos.sh` in diff
- [ ] `ServerConfig` has no `bearer_token`
- [ ] `start()` does not bind a port
- [ ] UniFFI scaffolding compiles (`cargo build`)

---

## Self-Review (plan vs spec)

| Spec requirement | Plan task |
|------------------|-----------|
| Rust workspace | Task 1 |
| UniFFI lifecycle API | Task 6 |
| ProviderBridge + mock | Task 5 |
| Config without bearer token | Task 3 |
| Stub start/stop (no HTTP) | Task 6 |
| just test-rust / lint-rust | Tasks 1–7 |
| No Swift changes | Task 7 |

No placeholders. All referenced types defined before use.
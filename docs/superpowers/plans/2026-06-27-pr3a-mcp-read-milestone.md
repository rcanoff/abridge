# PR 3a: MCP Read Milestone — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working milestone — Settings window (MCP + Permissions tabs) plus authenticated MCP JSON-RPC with two read-only Reminders tools returning real EventKit data.

**Architecture:** Swift Settings persists port + `eventkit.reminders.read` capability → `ServerConfig.enabled_capabilities` → Rust MCP router (`initialize`, `tools/list`, `tools/call`) with capability-gated tool registry → `ProviderBridge` → `EventKitProvider`. Popover links to Settings; minimal server controls remain in popover or move to Settings per preview.

**Tech Stack:** UniFFI 0.31, axum 0.8, serde_json, Swift 6, SwiftUI, Swift Testing, EventKit, UserDefaults

**Spec:** `docs/superpowers/specs/2026-06-27-pr3a-mcp-read-milestone-design.md`  
**Settings UX:** `docs/superpowers/specs/2026-06-27-settings-permissions-design.md`, preview `docs/superpowers/previews/settings-preview.html`  
**Branch:** `feat/pr3a-mcp-read-milestone`

---

## File Map

| File | Responsibility |
|------|----------------|
| **Rust — config & MCP** | |
| `rust/apple_bridge_core/src/config.rs` | Add `enabled_capabilities: Vec<String>` + validation |
| `rust/apple_bridge_core/src/capabilities.rs` | Allowlist + capability ID validation |
| `rust/apple_bridge_core/src/tools/mod.rs` | Tool registry (name, capability, provider, operation, schema) |
| `rust/apple_bridge_core/src/mcp/mod.rs` | JSON-RPC dispatch, method handlers |
| `rust/apple_bridge_core/src/mcp/protocol.rs` | Request/response types, error codes |
| `rust/apple_bridge_core/src/http.rs` | Pass `McpState` into `/mcp` handler |
| `rust/apple_bridge_core/src/server.rs` | Build router with config + provider arc |
| `rust/apple_bridge_core/tests/config_validation.rs` | Capability validation tests |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | HTTP JSON-RPC integration tests |
| `rust/apple_bridge_core/tests/support/port.rs` | `http_post_json` helper with bearer |
| **Swift — Settings** | |
| `AppleBridge/Models/AppSettings.swift` | Persist port, capability flags (UserDefaults) |
| `AppleBridge/Models/CapabilityCatalog.swift` | Shipped/planned capability metadata |
| `AppleBridge/Models/PermissionsStore.swift` | Permissions tab state + Apple/MCP derivation |
| `AppleBridge/Models/SettingsStore.swift` | MCP tab + window coordination |
| `AppleBridge/Views/Settings/SettingsWindowView.swift` | Sidebar MCP / Permissions |
| `AppleBridge/Views/Settings/MCPSettingsView.swift` | MCP tab UI |
| `AppleBridge/Views/Settings/PermissionsSettingsView.swift` | Permissions tree + tags |
| `AppleBridge/Views/MenuBarPopoverView.swift` | “Settings…” entry |
| `AppleBridge/AppleBridgeApp.swift` | Open Settings window (`openWindow` or `NSWindow`) |
| **Swift — EventKit** | |
| `AppleBridge/Providers/EventKit/EventKitProvider.swift` | `list_lists`, `list_reminders` |
| `AppleBridge/Providers/EventKit/EventKitReminderMapping.swift` | Pure mapping helpers (testable) |
| `AppleBridge/Providers/AppleProviderBridge.swift` | Dispatch `eventkit` |
| `AppleBridge/Services/ServerService.swift` | Port, capabilities → `ServerConfig` |
| `AppleBridge/Services/apple_bridge_core.swift` | **GENERATED** |
| **Tests** | |
| `AppleBridgeTests/PermissionsStoreTests.swift` | Derivation + MCP/Apple tags |
| `AppleBridgeTests/EventKitReminderMappingTests.swift` | JSON mapping unit tests |
| `AppleBridgeTests/MockEventKitStore.swift` | Protocol mock for EventKit |
| `AppleBridgeTests/ServerConfigCapabilitiesTests.swift` | Capability passed to createServer |

---

## Constants (use everywhere)

```text
CAPABILITY_READ = "eventkit.reminders.read"
TOOL_LIST_LISTS = "eventkit.reminders.list_lists"
TOOL_LIST_REMINDERS = "eventkit.reminders.list_reminders"
PROTOCOL_VERSION = "2024-11-05"
```

---

## Prerequisites

- [ ] `feat/pr2d-bearer-auth` merged to `main` (or branch from latest MCP auth work)
- [ ] `just lint-rust && just test-rust && just test-swift` green on base
- [ ] Read `docs/superpowers/previews/settings-preview.html` for UX target

---

### Task 1: Branch + `enabled_capabilities` on ServerConfig (TDD)

**Files:**
- Create: `rust/apple_bridge_core/src/capabilities.rs`
- Modify: `rust/apple_bridge_core/src/config.rs`, `lib.rs`
- Modify: all `ServerConfig { ... }` literals in `rust/apple_bridge_core/tests/` and `server.rs` unit test
- Test: `rust/apple_bridge_core/tests/config_validation.rs`

- [ ] **Step 1:** Checkout `feat/pr3a-mcp-read-milestone` from `main`

```bash
git checkout main && git pull && git checkout -b feat/pr3a-mcp-read-milestone
```

- [ ] **Step 2:** Failing tests

```rust
#[test]
fn accepts_read_capability() {
  let mut config = sample_config();
  config.enabled_capabilities = vec!["eventkit.reminders.read".into()];
  assert!(validate_config(&config).is_ok());
}

#[test]
fn rejects_unknown_capability() {
  let mut config = sample_config();
  config.enabled_capabilities = vec!["eventkit.foo.bar".into()];
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}

#[test]
fn rejects_uppercase_capability() {
  let mut config = sample_config();
  config.enabled_capabilities = vec!["EventKit.Reminders.Read".into()];
  assert!(matches!(validate_config(&config), Err(CoreError::InvalidConfig { .. })));
}
```

Add `enabled_capabilities: vec![]` to `sample_config()` and every other fixture.

- [ ] **Step 3:** Implement `capabilities.rs`

```rust
pub const READ: &str = "eventkit.reminders.read";

pub fn is_valid_capability_id(id: &str) -> bool {
  !id.is_empty()
    && id == id.to_lowercase()
    && !id.chars().any(char::is_whitespace)
    && id.split('.').count() >= 3
}

pub fn is_allowed_in_v1(id: &str) -> bool {
  matches!(id, READ)
}
```

In `validate_config`: validate shape + `is_allowed_in_v1` for each entry.

- [ ] **Step 4:** Add field to `ServerConfig`

```rust
pub enabled_capabilities: Vec<String>,
```

- [ ] **Step 5:** `TZ=UTC just test-rust` — config tests pass

---

### Task 2: Tool registry (TDD)

**Files:**
- Create: `rust/apple_bridge_core/src/tools/mod.rs`
- Modify: `lib.rs`

- [ ] **Step 1:** Failing unit tests in `tools/mod.rs` `#[cfg(test)]`

```rust
#[test]
fn lists_read_tools_when_capability_enabled() {
  let tools = tools_for_capabilities(&["eventkit.reminders.read".into()]);
  let names: Vec<_> = tools.iter().map(|t| t.name.as_str()).collect();
  assert_eq!(names, vec!["eventkit.reminders.list_lists", "eventkit.reminders.list_reminders"]);
}

#[test]
fn lists_no_tools_when_capability_empty() {
  assert!(tools_for_capabilities(&[]).is_empty());
}
```

- [ ] **Step 2:** Implement `ToolDefinition` + `tools_for_capabilities`

```rust
pub struct ToolDefinition {
  pub name: &'static str,
  pub capability: &'static str,
  pub provider: &'static str,
  pub operation: &'static str,
  pub description: &'static str,
}

pub fn all_tools() -> &'static [ToolDefinition] { /* two read tools */ }

pub fn tools_for_capabilities(enabled: &[String]) -> Vec<&'static ToolDefinition> {
  all_tools()
    .iter()
    .filter(|t| enabled.iter().any(|c| c == t.capability))
    .collect()
}

pub fn resolve_tool(name: &str) -> Option<&'static ToolDefinition> { /* ... */ }
```

- [ ] **Step 3:** `just test-rust` — pass

---

### Task 3: MCP JSON-RPC — `initialize` + `tools/list` (TDD)

**Files:**
- Create: `rust/apple_bridge_core/src/mcp/mod.rs`, `mcp/protocol.rs`
- Modify: `mcp.rs` (replace stub body), `http.rs`, `server.rs`, `lib.rs`
- Create: `rust/apple_bridge_core/tests/mcp_protocol.rs`
- Modify: `tests/support/port.rs`

- [ ] **Step 1:** Add `http_post_json` test helper (bearer + JSON body → status + body)

- [ ] **Step 2:** Failing integration tests

```rust
#[test]
fn mcp_initialize_returns_protocol_version() {
  // start server with enabled_capabilities: ["eventkit.reminders.read"]
  let body = r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#;
  let (status, resp) = mcp_post(body, TOKEN);
  assert_eq!(status, 200);
  assert!(resp.contains(r#""protocolVersion":"2024-11-05""#));
}

#[test]
fn mcp_tools_list_filtered_by_capability() {
  // with read capability → 2 tools
  // config with enabled_capabilities: [] → tools: []
}
```

- [ ] **Step 3:** Implement `McpState` in `http.rs`

```rust
pub struct McpState {
  pub bearer_token: String,
  pub enabled_capabilities: Vec<String>,
  pub provider: Arc<dyn ProviderBridge>,
}
```

`router(state: McpState) -> Router` — `/health` public; `/mcp` auth + post handler.

- [ ] **Step 4:** `handle_mcp` parses JSON-RPC, dispatches:

| Method | Action |
|--------|--------|
| `initialize` | Return spec result |
| `tools/list` | `tools_for_capabilities` → JSON schemas |
| `notifications/initialized` | Empty 204 or `{"jsonrpc":"2.0","result":{}}` |
| other | `-32601` |

- [ ] **Step 5:** `server.rs` builds `McpState` from `ServerInner` at start (clone config + provider arc)

- [ ] **Step 6:** Update `http_auth.rs` — valid token now returns 200 JSON-RPC (not 501) for `initialize`

- [ ] **Step 7:** `TZ=UTC just lint-rust && just test-rust`

---

### Task 4: MCP `tools/call` + capability gate (TDD)

**Files:**
- Modify: `mcp/mod.rs`, `tools/mod.rs`
- Modify: `tests/mcp_protocol.rs`, `tests/provider_bridge.rs`

- [ ] **Step 1:** Failing tests

```rust
#[test]
fn tools_call_dispatches_to_provider() {
  // MockProviderBridge records provider+operation
  // call list_lists → ProviderRequest { eventkit, list_lists, "{}" }
}

#[test]
fn tools_call_capability_disabled_without_provider_call() {
  // enabled_capabilities: [] → isError true, code capability_disabled
  // mock call_count == 0
}

#[test]
fn tools_call_unknown_tool() {
  // name: "nope" → unknown_tool
}
```

- [ ] **Step 2:** Implement `tools/call`

- Map tool → `ToolDefinition`
- Check capability in config
- Build `ProviderRequest { provider, operation, payload_json: arguments }`
- Call `provider.call_provider`
- On `ok`: MCP result `{ content: [{ type: "text", text: payload_json }], isError: false }`
- On provider error: parse `error_json` → `isError: true`

- [ ] **Step 3:** `just test-rust` — all Rust tests pass

- [ ] **Step 4:** `just build-rust` — commit generated `apple_bridge_core.swift`

---

### Task 5: Settings shell + popover entry

**Skills:** swiftui-pro, swift-concurrency-pro before Swift edits.

**Files:**
- Create: `AppleBridge/Views/Settings/SettingsWindowView.swift`
- Modify: `AppleBridge/AppleBridgeApp.swift`, `MenuBarPopoverView.swift`
- Modify: `project.yml` if needed; run `xcodegen generate`

- [ ] **Step 1:** Add `Settings` scene — `Window("Settings", id: "settings") { SettingsWindowView() }`

- [ ] **Step 2:** Sidebar with `MCP` and `Permissions` tabs (match preview layout)

- [ ] **Step 3:** Popover button `Settings…` → `openWindow(id: "settings")`

- [ ] **Step 4:** Build succeeds; manual open Settings window

---

### Task 6: MCP settings tab

**Files:**
- Create: `AppleBridge/Models/AppSettings.swift`, `SettingsStore.swift`
- Create: `AppleBridge/Views/Settings/MCPSettingsView.swift`
- Modify: `ServerService.swift`, `ServerStore.swift`

- [ ] **Step 1:** `AppSettings` UserDefaults keys: `mcpPort` (default 3020), `mcpEnabled` (bool)

- [ ] **Step 2:** MCP tab UI: enable toggle, status, host read-only, port field, endpoint line, bearer copy/reset (reuse KeychainService)

- [ ] **Step 3:** Wire enable toggle → `ServerStore.startServer` / `stopServer`

- [ ] **Step 4:** Port change → stop, recreate handle, start (extend `ServerService` like host/port/token change)

- [ ] **Step 5:** Reset token → Keychain rotate + server restart (existing KeychainService)

- [ ] **Step 6:** Build + manual smoke: toggle server from Settings

---

### Task 7: Permissions tab

**Files:**
- Create: `CapabilityCatalog.swift`, `PermissionsStore.swift`, `PermissionsSettingsView.swift`
- Test: `AppleBridgeTests/PermissionsStoreTests.swift`

- [ ] **Step 1:** `CapabilityCatalog` — Reminders rows (read shipped, others `shipped: false`); calendar stub

- [ ] **Step 2:** `PermissionsStore` — load/save checked caps; compute Apple + MCP tags per preview logic

- [ ] **Step 3:** Summary card: MCP active line + Apple macOS line

- [ ] **Step 4:** Save button → persist; if Read checked, set `enabled_capabilities` path for server; call `RemindersPermissionService` when Apple needed

- [ ] **Step 5:** Swift tests for tag derivation (`Read` → MCP active + Apple granted; `Create` unshipped → MCP blocked)

- [ ] **Step 6:** `just test-swift`

---

### Task 8: Wire capabilities into ServerService

**Files:**
- Modify: `ServerService.swift`, `ServerStore.swift`, `AppSettings.swift`
- Test: `AppleBridgeTests/ServerConfigCapabilitiesTests.swift`

- [ ] **Step 1:** When Read saved in permissions, pass `enabledCapabilities: ["eventkit.reminders.read"]` to `ServerConfig`

- [ ] **Step 2:** Recreate server handle when capabilities change (track `currentCapabilities` like token/host)

- [ ] **Step 3:** Test: mock seam verifies `createServer` receives capability vector

- [ ] **Step 4:** `just build-rust` if FFI touched; `just test-swift`

---

### Task 9: EventKitProvider — `list_lists` + `list_reminders` (TDD)

**Skills:** swiftui-pro, swift-testing-pro, swift-concurrency-pro

**Files:**
- Create: `EventKitProvider.swift`, `EventKitReminderMapping.swift`
- Create: `MockEventKitStore.swift`, `EventKitReminderMappingTests.swift`
- Modify: `AppleProviderBridge.swift`

- [ ] **Step 1:** Protocol `EventKitStoreing` for test seam (`reminderCalendars()`, `fetchReminders(matching:)`)

- [ ] **Step 2:** Failing mapping tests (no live EventKit)

```swift
@Test func mapsCalendarToListJSON() { /* id, title, source */ }

@Test func mapsReminderFields() { /* id, title, completed, due_date, notes */ }
```

- [ ] **Step 3:** `EventKitProvider.handle` switches on `operation`:

```swift
case "list_lists": return listLists()
case "list_reminders": return listReminders(payloadJson: request.payloadJson)
default: return unknown_operation
```

- [ ] **Step 4:** `list_reminders` parses optional `list_id` from arguments JSON

- [ ] **Step 5:** Permission denied → `error_json` `{ "code": "permission_denied" }`

- [ ] **Step 6:** `AppleProviderBridge` routes `eventkit` → `EventKitProvider`

- [ ] **Step 7:** `just test-swift` — pass

---

### Task 10: End-to-end verification

- [ ] **Step 1:** `TZ=UTC just lint-rust && just test-rust`

- [ ] **Step 2:** `just build-rust`

- [ ] **Step 3:** `TZ=UTC just test-swift`

- [ ] **Step 4:** Manual smoke

```bash
# App: Settings → enable Read + Save → enable MCP server
# Note token from MCP tab

curl -s -X POST http://127.0.0.1:3020/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'

curl -s -X POST http://127.0.0.1:3020/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"eventkit.reminders.list_lists","arguments":{}}}'
```

- [ ] **Step 5:** `just review` — triage; fix agreed issues

---

### Task 11: Popover cleanup (optional same PR)

- [ ] Move bearer token display from popover to Settings-only (or keep copy shortcut in popover — pick one in implementation; default: **Settings only** per preview)

- [ ] Popover retains server status summary + “Settings…” link

---

## Spec coverage self-review

| Spec requirement | Task |
|------------------|------|
| Settings MCP tab | 5, 6 |
| Settings Permissions tab | 7 |
| `enabled_capabilities` FFI | 1, 8 |
| MCP initialize / tools/list / tools/call | 3, 4 |
| Two read tools | 2, 4, 9 |
| Capability gate | 2, 4 |
| EventKitProvider | 9 |
| Manual smoke | 10 |
| Read-only; writes blocked in UI | 7 |
| Auth on /mcp | 3 (existing auth layer) |

---

## Success criteria (from spec)

- [ ] Settings window matches preview structure (sidebar MCP / Permissions)
- [ ] Read capability gates tools; unshipped rows MCP-blocked
- [ ] `just build-rust` + `just test-all` pass
- [ ] Real reminder data via both tools with OS permission granted
- [ ] Review loop complete

---

## Agent notes

**Swift skills required** before Swift edits: swiftui-pro, swift-testing-pro, swift-concurrency-pro.

**Rust skills:** rust-best-practices, `rust/AGENTS.md`.

**Generated code:** Never hand-edit `apple_bridge_core.swift`.

**Lifecycle tests:** Hold `LIFECYCLE_TEST_LOCK` in all `server_lifecycle` tests when adding new parallel tests.

**Commit gate:** Do not commit until user says ready.

**Review triage:** One table per `AGENTS.md` when acting on review feedback.
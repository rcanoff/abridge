# PR 2d: Bearer Auth + Keychain + Stub `/mcp` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add bearer token auth to the embedded HTTP server (all routes except `GET /health`), Keychain-backed token storage in Swift, and a stub `POST /mcp` that requires auth and returns structured not-implemented.

**Architecture:** Swift `KeychainService` loads/creates token → `ServerService` injects into `ServerConfig.bearer_token` → Rust `auth.rs` middleware validates `Authorization: Bearer` with constant-time compare → `mcp.rs` stub handler. Popover shows copyable token. Server handle recreates when host/port/token changes.

**Tech Stack:** UniFFI 0.31, axum 0.8 middleware, Security framework, Swift 6, Swift Testing

**Spec:** `docs/superpowers/specs/2026-06-27-pr2-mcp-server-design.md` § PR 2d preview  
**Branch:** `feat/pr2d-bearer-auth`

---

## File Map

| File | Responsibility |
|------|----------------|
| `rust/apple_bridge_core/src/config.rs` | Add `bearer_token`; validate non-empty |
| `rust/apple_bridge_core/src/auth.rs` | Bearer header parse + constant-time compare |
| `rust/apple_bridge_core/src/mcp.rs` | Stub `POST /mcp` → 501 JSON not-implemented |
| `rust/apple_bridge_core/src/http.rs` | Public `/health`; protected `/mcp` with auth layer |
| `rust/apple_bridge_core/src/server.rs` | Pass token into `http::router()` |
| `rust/apple_bridge_core/tests/config_validation.rs` | `rejects_empty_bearer_token` |
| `rust/apple_bridge_core/tests/http_auth.rs` | Auth + `/mcp` stub integration tests |
| `rust/apple_bridge_core/tests/support/port.rs` | `http_post` helper with optional auth header |
| `AppleBridge/Services/KeychainService.swift` | Load or create bearer token (Keychain) |
| `AppleBridge/Services/ServerService.swift` | Inject token; recreate handle on token change |
| `AppleBridge/Services/ServerServing.swift` | Add `loadBearerToken()` for UI |
| `AppleBridge/Models/ServerStore.swift` | Load/display bearer token |
| `AppleBridge/Views/MenuBarPopoverView.swift` | Copyable token row |
| `AppleBridge/Services/apple_bridge_core.swift` | **GENERATED** — regen via `just build-rust` |
| `AppleBridgeTests/MockServerService.swift` | Mock `loadBearerToken` |
| `AppleBridgeTests/KeychainServiceTests.swift` | Round-trip load/create (real Keychain) |

---

## Prerequisites

- [ ] On `main` with PR 2c merged
- [ ] `just test-rust` and `just test-swift` green on `main`

---

### Task 1: Rust config + validation (TDD)

**Files:** `config.rs`, `config_validation.rs`, all `ServerConfig` literals in tests

- [ ] **Step 1:** Failing test `rejects_empty_bearer_token`
- [ ] **Step 2:** Add `bearer_token: String` to `ServerConfig`; validate non-empty in `validate_config()`
- [ ] **Step 3:** Update all test fixtures with `bearer_token: "test-token".into()`
- [ ] **Step 4:** `just test-rust` — config tests pass

---

### Task 2: Rust auth + mcp + HTTP routes (TDD)

**Files:** `auth.rs`, `mcp.rs`, `http.rs`, `lib.rs`, `http_auth.rs`, `support/port.rs`

- [ ] **Step 1:** Failing tests: `/health` no auth OK; `/mcp` without token → 401; wrong token → 401; valid token → 501 stub JSON
- [ ] **Step 2:** Implement `auth.rs` (parse `Bearer`, constant-time eq, never log token)
- [ ] **Step 3:** Implement `mcp.rs` stub (`not_implemented` JSON)
- [ ] **Step 4:** `http::router(bearer_token)` — `/health` public; `/mcp` behind auth middleware
- [ ] **Step 5:** `server.rs` passes `config.bearer_token` to router
- [ ] **Step 6:** `just lint-rust && just test-rust`

---

### Task 3: UniFFI regen

- [ ] **Step 1:** `just build-rust`
- [ ] **Step 2:** Commit generated `apple_bridge_core.swift` (never hand-edit)

---

### Task 4: Swift Keychain + ServerService

**Files:** `KeychainService.swift`, `ServerService.swift`, `ServerServing.swift`

- [ ] **Step 1:** `KeychainService` — `loadOrCreateBearerToken()`, service `com.applebridge.AppleBridge.mcp-bearer-token`
- [ ] **Step 2:** `ServerService` loads token on start; passes `bearerToken` to `ServerConfig`; recreates handle on token/host/port change
- [ ] **Step 3:** `ServerServing.loadBearerToken()` for UI preload
- [ ] **Step 4:** Map `InvalidConfig` for empty token in user messages

---

### Task 5: ServerStore + UI + tests

**Files:** `ServerStore.swift`, `MenuBarPopoverView.swift`, tests

- [ ] **Step 1:** `ServerStore` loads token on init/refresh; exposes `bearerToken` for popover
- [ ] **Step 2:** Popover: "Bearer Token" label + copyable monospaced text
- [ ] **Step 3:** `KeychainServiceTests` + update `MockServerService`
- [ ] **Step 4:** `just test-swift`

---

### Task 6: Verification + review

- [ ] `just lint-rust && just test-rust`
- [ ] `just build-rust`
- [ ] `just test-swift`
- [ ] Manual: Start server → `curl /health` OK without auth; `curl -X POST /mcp` 401; with token 501
- [ ] `just review` → triage; fix agreed substantive issues
- [ ] Push `feat/pr2d-bearer-auth`

---

## Success Criteria

- [ ] `bearer_token` on `ServerConfig` with validation
- [ ] Auth enforced on `/mcp`; `/health` remains public
- [ ] Keychain load/create in Swift; token in popover (copyable)
- [ ] Server recreates on token change
- [ ] All Rust + Swift tests pass
- [ ] No full MCP protocol, no auto-start

---

## Non-goals

- Full MCP JSON-RPC handler
- EventKit tools
- Auto-start on launch
- Token rotation UI (restart required on rotate — document only)
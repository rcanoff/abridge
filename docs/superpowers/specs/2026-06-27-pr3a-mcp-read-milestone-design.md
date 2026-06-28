# PR 3a: MCP Read Milestone — Design Spec

**Date:** 2026-06-27  
**Status:** Approved (brainstorming)  
**Branch:** `feat/pr3a-mcp-read-milestone`  
**PRD:** `docs/prd.md` § EventKit / V1 Scope  
**Architecture:** `docs/architecture-bootstrap-guide.md`  
**Related:** `docs/superpowers/specs/2026-06-27-settings-permissions-design.md`  
**Predecessor:** PR 2d (bearer auth, MCP 501 stub)

---

## Summary

One **working product milestone**: Settings window (MCP + Permissions tabs) plus a real MCP server that exposes two read-only Reminders tools backed by EventKit.

A client can authenticate, run `initialize`, discover tools, call `eventkit.reminders.list_lists` / `list_reminders`, and receive real Apple data. Only the **Read** capability is MCP-active; other permission rows remain blocked per the settings design.

---

## Goals

| # | Deliverable |
|---|-------------|
| 1 | Settings window — MCP tab (enable, port, token, endpoint) |
| 2 | Settings window — Permissions tab (tree, Apple/MCP tags, Read active) |
| 3 | MCP JSON-RPC on `POST /mcp`: `initialize`, `tools/list`, `tools/call` |
| 4 | Tools: `eventkit.reminders.list_lists`, `eventkit.reminders.list_reminders` |
| 5 | Swift `EventKitProvider` — thin EKEventStore adapters |
| 6 | Rust capability gate — Read required for read tools |
| 7 | Manual smoke: MCP client or curl against localhost |

## Non-goals

- Create / Edit / Delete / Complete / Alarms / Recurrence / Search tools
- Calendar domain (stub UI only)
- Auto-start server, launch at login, logs/diagnostics tabs
- MCP resources, prompts, sampling, roots
- `notifications/initialized` session state machine beyond minimal accept-and-continue
- Search/filter beyond optional `list_id` on `list_reminders`

---

## Approach

**Selected: Approach 2 — Read pair (initialize + two list tools + Settings)**

### Rejected

| Alternative | Reason |
|-------------|--------|
| Protocol-only PR | Not a working milestone (user requirement) |
| `list_lists` only | Too weak a demo |
| Full read bundle in one PR | Too large; violates small-feature splits inside the PR |

---

## Architecture

```
Settings (Swift)
  → persists port, capabilities, MCP enable
  → ServerService → ServerConfig (host, port, bearer_token, enabled_capabilities, …)
  → create_server / start_server

MCP client
  → POST /mcp + Bearer
  → mcp.rs: JSON-RPC dispatch
  → tools/list: registry filtered by enabled capabilities
  → tools/call: capability check → map tool name → provider + operation
  → ProviderBridge.call_provider(ProviderRequest)
  → AppleProviderBridge → EventKitProvider
  → EKEventStore
  → ProviderResponse JSON → MCP tool result
```

### Layer responsibilities

| Layer | Owns |
|-------|------|
| **Settings UI** | Capability toggles, MCP config, Apple/MCP transparency |
| **Rust `mcp.rs`** | JSON-RPC, tool registry, capability enforcement |
| **Rust routing** | Tool name → `provider` + `operation`; request validation |
| **Swift `EventKitProvider`** | EKEventStore calls, JSON serialization only |
| **Apple** | Coarse Reminders TCC (requested via existing permission flow) |

---

## Settings (this PR)

Implements `docs/superpowers/specs/2026-06-27-settings-permissions-design.md` with:

- **MCP tab** — full behavior (not preview-only)
- **Permissions tab** — all Reminders rows visible; only **Read** shipped (`MCP active` when saved)
- **Entry** — popover link “Settings…”
- **Persistence** — UserDefaults or small settings file (Swift); no app database

Capability flag passed to Rust on server (re)create:

| Capability ID | Gates |
|---------------|-------|
| `eventkit.reminders.read` | `list_lists`, `list_reminders` |

Unshipped rows (Create, Edit, …) remain selectable for transparency but always `MCP blocked`.

---

## UniFFI / config changes

Add to `ServerConfig` (additive FFI change → `just build-rust`):

```rust
pub struct ServerConfig {
  pub host: String,
  pub port: u16,
  pub bearer_token: String,
  pub enabled_providers: Vec<ProviderConfig>,
  pub enabled_capabilities: Vec<String>,  // NEW
}
```

Validation (`validate_config`):

- Each capability: non-empty, lowercase, `provider.domain.action` shape (document matrix row in architecture guide when implementing)
- Unknown capability IDs rejected at config time
- PR 3a allowlist: `eventkit.reminders.read` only

Server restart required when capabilities, port, or token change (existing ServerService pattern).

---

## MCP protocol (HTTP JSON-RPC)

**Transport:** Existing `POST /mcp` (authenticated). One JSON-RPC request per POST; JSON response body. No SSE in this PR.

**Protocol version:** `2024-11-05` (architecture smoke example).

### Supported methods

| Method | Behavior |
|--------|----------|
| `initialize` | Return `protocolVersion`, `serverInfo`, `capabilities.tools` |
| `tools/list` | Return tools filtered by enabled capabilities |
| `tools/call` | Dispatch by name; return `content` or structured error |
| `notifications/initialized` | Accept; no-op (stateless HTTP) |
| Other methods | JSON-RPC `-32601` method not found |

### `initialize` result (minimal)

```json
{
  "protocolVersion": "2024-11-05",
  "capabilities": { "tools": {} },
  "serverInfo": { "name": "apple-bridge", "version": "0.1.0" }
}
```

### `tools/list` result

Array of tool descriptors with `name`, `description`, `inputSchema` (JSON Schema subset).

### `tools/call`

**Params:** `{ "name": "<tool>", "arguments": { ... } }`

**Result:** `{ "content": [ { "type": "text", "text": "<json string>" } ], "isError": false }`

**Errors:** MCP tool error with `isError: true` or JSON-RPC error for protocol faults.

---

## Tools (v1 read pair)

### `eventkit.reminders.list_lists`

| Field | Value |
|-------|--------|
| Capability | `eventkit.reminders.read` |
| Dispatch | `provider: "eventkit"`, `operation: "list_lists"` |
| Arguments | `{}` (empty object) |
| Payload | JSON array of `{ "id", "title", "source" }` — faithful EKCalendar fields, minimal set |

### `eventkit.reminders.list_reminders`

| Field | Value |
|-------|--------|
| Capability | `eventkit.reminders.read` |
| Dispatch | `provider: "eventkit"`, `operation: "list_reminders"` |
| Arguments | `{ "list_id": "<string>"? }` — optional; omit = all lists |
| Payload | JSON array of reminder objects: `id`, `title`, `completed`, `due_date` (ISO8601 or null), `notes` (optional) |

Tool names are the MCP surface; internal dispatch uses `snake_case` operations per `docs/conventions.md`.

---

## Capability enforcement (MCP layer)

Before `ProviderBridge` call:

1. Resolve tool → required capability (`eventkit.reminders.read`)
2. If capability not in `ServerConfig.enabled_capabilities` → tool error `capability_disabled` (do not call Swift)
3. If provider disabled in `enabled_providers` → `provider_disabled`
4. Validate `operation` shape at routing layer (existing conventions)

`tools/list` exposes only tools whose capability is enabled.

---

## EventKit provider (Swift)

**New files:**

```
AppleBridge/Providers/EventKit/
  EventKitProvider.swift
```

**`AppleProviderBridge`** dispatches `eventkit` → `EventKitProvider`.

Rules (architecture guide):

- Thin adapter — no business logic
- Permission: assume Settings / popover already requested access; return structured `permission_denied` if EK denies
- Serialize Apple types to JSON strings in `payload_json`
- Errors in `error_json`: `{ "code": "permission_denied" | "eventkit_error", "message": "..." }`

**Tests:** Swift Testing for JSON mapping with injected protocol mocks; no live EventKit in CI.

---

## Error handling

| Condition | MCP / HTTP |
|-----------|------------|
| Missing/invalid Bearer | 401 (existing auth) |
| Unknown JSON-RPC method | `-32601` |
| Malformed JSON-RPC | `-32600` |
| Unknown tool | Tool error `unknown_tool` |
| Capability off | Tool error `capability_disabled` |
| EventKit permission denied | Tool error `permission_denied` |
| UniFFI/provider failure | Tool error `provider_error` |

Never log bearer tokens or reminder content at info level.

---

## Internal task breakdown (one PR, small commits)

| Task | Scope |
|------|--------|
| 3a-1 | Settings shell + popover entry |
| 3a-2 | MCP tab wired to ServerStore/Service |
| 3a-3 | Permissions tab + capability persistence + tags |
| 3a-4 | `ServerConfig.enabled_capabilities` + validation |
| 3a-5 | `mcp.rs` JSON-RPC + `initialize` / `tools/list` |
| 3a-6 | Tool registry + capability filter |
| 3a-7 | `tools/call` routing → ProviderBridge |
| 3a-8 | `EventKitProvider` `list_lists` |
| 3a-9 | `EventKitProvider` `list_reminders` |
| 3a-10 | Rust integration tests (mock provider + MCP HTTP) |
| 3a-11 | Swift tests + manual smoke checklist |

---

## Testing

| Area | Minimum |
|------|---------|
| Rust | `initialize`, `tools/list` filtered by capability, `tools/call` dispatches mock provider, `capability_disabled` without Swift call |
| Rust | Auth still required on `/mcp` |
| Swift | Settings persistence, capability → ServerConfig, EventKit mapper unit tests |
| Manual | Start server from Settings; curl `initialize` + `tools/call` with token; MCP client lists reminders |

`TZ=UTC` for all test commands.

---

## Success criteria

- [ ] Settings window: MCP + Permissions tabs match approved preview behavior
- [ ] Read capability gates read tools; other rows MCP-blocked
- [ ] `just build-rust` + `just test-all` pass
- [ ] Real Reminders data returned via both tools when OS permission granted
- [ ] Client smoke documented in plan (curl or named MCP client)

---

## Open items

None. Implementation plan (`writing-plans`) will define file-level steps and review checkpoints.
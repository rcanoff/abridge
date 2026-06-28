# Settings & Permissions UI — Design Spec

**Date:** 2026-06-27  
**Status:** Approved (brainstorming)  
**PRD:** `docs/prd.md` § User Interface  
**Architecture:** `docs/architecture-bootstrap-guide.md`  
**Preview:** `docs/superpowers/previews/settings-preview.html`  
**Predecessor:** PR 2d (bearer auth, MCP stub)

---

## Summary

Apple Bridge gets a **Settings** window (separate from the menu bar popover) with two tabs:

1. **MCP** — server enable/disable, host/port, endpoint, bearer token copy/reset  
2. **Permissions** — ABAC-style EventKit capability tree with transparent **Apple vs MCP** enforcement

The popover remains minimal (status + link to Settings). Capability toggles drive future MCP tool exposure; macOS TCC is requested only when selections require it.

---

## Goals

- Config surface for MCP (port, token, server on/off) per PRD
- Granular **app capabilities** (Read, Create, Edit, …) — not 1:1 with Apple TCC
- Transparent dual enforcement on every row: **Apple** (macOS) vs **MCP** (Apple Bridge)
- Progressive disclosure: only **shipped** capabilities are MCP-enforceable; unshipped rows show **MCP blocked**
- Honest Apple summary before system dialogs

## Non-goals (this spec)

- Full MCP JSON-RPC protocol (PR 3a+)
- EventKit provider implementation
- Calendar MCP tools (UI stub only)
- Launch at login, diagnostics, logs tabs
- Auto-start server on launch

---

## Settings window

| Element | Behavior |
|---------|----------|
| **Chrome** | macOS window; sidebar tabs: MCP, Permissions |
| **Entry** | Menu bar popover → “Settings…” (popover keeps server status only) |
| **Persistence** | Swift-side settings (capability flags, port); Keychain for token; no user data DB |

### MCP tab

| Control | Notes |
|---------|-------|
| Enable server | Master toggle → start/stop embedded server |
| Status | Running / Stopped |
| Host | Read-only `127.0.0.1` (loopback rule) |
| Port | User-editable; default `3020`; restart on change |
| Endpoint | Derived `http://127.0.0.1:<port>/mcp` |
| Bearer token | Read-only display, Copy, **Reset token** (Keychain rotate + server restart) |

### Permissions tab

**Summary card (top):**

| Row | Shows |
|-----|--------|
| **MCP** | Active capabilities in Apple Bridge, or `Blocked: …` for selected-but-unshipped |
| **Apple** | Coarse macOS grant state (e.g. `Reminders — Full access`) |

**Tree:**

```
▼ EventKit
    Reminders
      [ ] Read, Create, Edit, Delete, Complete, Alarms, Recurrence, Search
      each row: [Apple tag] [MCP tag]
    Calendar — coming later (disabled)
```

**Legend:** `Apple = macOS access · MCP = enforced by Apple Bridge`

**Actions:** Save / Save changes → persist capability config; request Apple access when needed.

---

## Two-layer permission model

### Layer 1 — Capabilities (app / MCP)

User-facing toggles. Drive:

- Which MCP tools are registered/exposed (when shipped)
- Rust routing enforcement
- Persisted in app settings → reflected in `ServerConfig` / capability manifest when server starts

**v1 Reminders groups (option B):** Read, Create, Edit, Delete, Complete, Alarms, Recurrence, Search.

**Progressive shipping:**

| State | Toggle | MCP tag |
|-------|--------|---------|
| Shipped + saved + on | Enabled | `MCP active` |
| Shipped + unsaved change | Enabled | `MCP pending` |
| Shipped + off | — | `MCP off` |
| Not shipped | May check (intent) | `MCP blocked` |

Add capabilities to the catalog as MCP tools ship; unshipped rows never become MCP-active.

### Layer 2 — Apple access (macOS)

Derived from checked capabilities. Shown in summary + per-row **Apple** tag:

| Tag | Meaning |
|-----|---------|
| `Apple —` | Not selected / not needed |
| `Apple needed` | Selection requires macOS prompt |
| `Apple granted` | TCC satisfied for Reminders (or Calendar later) |

**Derivation rules (Reminders):**

| User selects | Apple request (plain copy) |
|--------------|----------------------------|
| Read only | Full Access (Apple has no list-only tier) |
| Create only | Write-only or Full (product choice at implement) |
| Edit, Delete, or Read+write | Full Access |

**Transparency copy** when user selects unshipped capability (e.g. Create):

> Create — Apple may grant access, but **MCP blocks** until shipped.

### Key product rule

> Apple grants coarse access. MCP enforces fine-grained capabilities. The UI must never imply Apple controls Create/Edit/Delete separately.

---

## Data flow

```
User toggles capabilities in Settings
  → Swift persists capability flags
  → Summary computes Apple requirement
  → [Save] → request EventKit if needed
  → Server restart with updated config / tool registry (when MCP tools exist)

MCP client calls tool
  → Rust auth + capability check (MCP layer)
  → ProviderBridge → EventKit (requires Apple layer already granted)
```

---

## Relationship to PR 3

| Work | Suggested order |
|------|-----------------|
| Settings shell + MCP tab + capability catalog (Read only shipped) | Can land before or with PR 3a |
| MCP protocol + first tool (list reminders) | PR 3a |
| Enable Create/Edit/… rows as tools ship | Incremental |

Permissions UI can land early with only **Read** MCP-active; other rows show `MCP blocked` until their PR.

---

## Testing

| Layer | Approach |
|-------|----------|
| Swift | Swift Testing — settings store, capability persistence, Apple derivation logic (pure functions) |
| UI | Manual smoke on Settings window |
| EventKit dialogs | Manual only (conventions) |

---

## Success criteria

- [ ] Settings window with MCP + Permissions tabs matches preview structure
- [ ] MCP tab: enable/disable, port, token copy/reset
- [ ] Permissions: capability tree, summary, dual tags per row
- [ ] Selecting unshipped capability shows Apple granted + MCP blocked when OS already granted
- [ ] Save persists capability flags; Apple prompt only when needed
- [ ] Popover links to Settings; does not duplicate full config

---

## Open items

None for UI design. Implementation plan to define: settings persistence format, capability ID strings aligned with `docs/conventions.md` tool naming, and PR split (settings-only PR vs combined with PR 3a).
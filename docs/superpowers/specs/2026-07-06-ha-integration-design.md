# HA Integration — Design Spec

**Status:** Draft — pending user review  
**Date:** 2026-07-06  
**Feature name:** HA Integration (Home Assistant Integration)

---

## Summary

Add an optional **HA Integration** to Apple Bridge: a Mac-side sync layer that connects Apple frameworks to Home Assistant over the LAN. Users configure connection credentials once, then use checklists in the Mac app to choose which Reminder lists and Calendar calendars sync, with optional location sharing and bridge health sensors.

Apple Bridge remains a generic Apple framework bridge for MCP. HA Integration is an opt-in consumer of `ProviderBridge` — it does not change MCP payloads or provider fidelity.

---

## Goals

- Two-way sync: Apple Reminders ↔ HA `local_todo` entities
- Two-way sync: Apple Calendar events ↔ HA `calendar` entities
- One-way push: Mac location → HA `device_tracker`
- One-way push: Apple Bridge operational status → HA sensors
- User selects synced Reminder lists and Calendar calendars via checklists in the Mac app
- Sync runs on the Mac (EventKit/MapKit live here); HA is reached outbound over LAN
- Independent of MCP capability toggles (Integrations has its own enable gates)

## Non-goals (V1)

- Contacts sync
- Vision / OCR / QR sync
- MapKit geocoding, routing, or place search in HA Integration (MCP only)
- Exposing Apple Bridge MCP on LAN or changing localhost-only bind
- HA as a Swift/Rust “provider” alongside EventKit
- Real-time HA webhooks to Mac (polling only in V1)
- Cloud / remote HA without user-supplied URL

---

## Architecture

### Process model

HA Integration runs inside the Apple Bridge app process as a Rust-owned background task (tokio), started/stopped from Swift via UniFFI.

```
┌─────────────────────────────────────────────────────────────────┐
│ Apple Bridge.app                                                │
│                                                                 │
│  Integrations UI (Swift) ──► HAIntegrationConfig (UniFFI)       │
│                                      │                          │
│                                      ▼                          │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Rust: ha_integration                                      │  │
│  │  • sync scheduler (per-domain poll intervals)           │  │
│  │  • reminders_sync (two-way)                               │  │
│  │  • calendar_sync (two-way)                                │  │
│  │  • location_push (one-way)                                │  │
│  │  • status_push (one-way)                                  │  │
│  │  • ha_rest_client (reqwest → HA REST API)                 │  │
│  │  • sync_state persistence (metadata only)                 │  │
│  └───────────────┬─────────────────────┬─────────────────────┘  │
│                  │ ProviderBridge      │ HTTPS/HTTP LAN          │
│                  ▼                     ▼                          │
│           EventKit / MapKit      Home Assistant                 │
└─────────────────────────────────────────────────────────────────┘
```

### Why Mac-initiated sync

- Apple Bridge binds `127.0.0.1` by default; HA typically runs on separate hardware
- EventKit and MapKit location require the Mac process
- Outbound LAN calls to HA preserve localhost-only MCP security

### Layer responsibilities

| Layer | Owns |
|-------|------|
| **Swift UI** | Integrations tab, checklists, connection test, Keychain for HA token |
| **Swift stores** | Persist user selections (list/calendar IDs, toggles, intervals) |
| **Rust `ha_integration`** | Sync algorithms, HA REST client, diff/merge, loop prevention, state file |
| **Rust `ProviderBridge`** | All Apple framework reads/writes (same path as MCP, no HTTP loopback) |
| **MCP server** | Unchanged; independent of HA Integration |

---

## User interface — Integrations tab

New settings tab: **Integrations** (sidebar item between Diagnostics and Developer, or after Permissions).

### Connection section

| Field | Storage | Notes |
|-------|---------|-------|
| Home Assistant URL | App settings | Default `http://homeassistant.local:8123` |
| Long-lived access token | Keychain | Never logged; masked in UI |
| Test connection | — | Calls `GET /api/` with Bearer token |

### Reminders section

- Master toggle: enable Reminders sync
- Checklist of all EventKit reminder lists (`list_lists`)
- Per-list row: name, sync status, linked HA entity ID, last sync time
- On enable new list: auto-create HA `local_todo` entity named after the list (slugified entity ID)
- On disable list: stop sync; prompt whether to delete HA entity (default: keep)

**Permission:** Reminders (EventKit) — same as MCP reminders; not gated on MCP capability checkboxes.

### Calendar section

- Master toggle: enable Calendar sync
- Checklist of all EventKit event calendars (`list_calendars`)
- Same enable/disable/link behavior as Reminders
- On enable new calendar: auto-create or link HA calendar entity

**Permission:** Calendars (EventKit).

### Location section

- Toggle: Share Mac location with HA
- Interval picker: 1 / 5 / 15 minutes (default 5)
- Target: single `device_tracker` entity (default `device_tracker.apple_bridge_mac`)

**Permission:** Location (MapKit). One-way only.

### Bridge status section

- Toggle: Expose bridge health in HA
- Creates/updates:
  - `binary_sensor.apple_bridge_mcp_running`
  - `binary_sensor.apple_bridge_ha_integration_enabled`
  - `sensor.apple_bridge_ha_last_sync_reminders` (timestamp)
  - `sensor.apple_bridge_ha_last_sync_calendar` (timestamp)
  - `binary_sensor.apple_bridge_ha_sync_healthy` (any domain error-free)

### Global sync interval

Default poll interval for Reminders and Calendar (30s / 60s / 5m; default 60s). Location uses its own interval.

---

## Sync semantics

### Identity keys

| Apple | HA | Domain |
|-------|-----|--------|
| `calendar_item_identifier` | Todo `uid` | Reminders |
| `calendar_item_identifier` | Calendar event `uid` | Calendar events |
| `calendar_identifier` | Maps to HA list/calendar entity | Container |

Use Apple `calendar_item_identifier` as HA `uid` when pushing Apple → HA. When HA originates an item, create on Apple first via ProviderBridge, then set HA `uid` from returned `calendar_item_identifier`.

### Field mapping — Reminders

| Apple (EventKit) | HA (TodoItem) |
|------------------|---------------|
| `title` | `summary` |
| `notes` | `description` |
| `is_completed` | `status` (NEEDS_ACTION / COMPLETE) |
| `due_date` / `start_date` | `due` |
| `last_modified_date` | change detection |

### Field mapping — Calendar events

| Apple (EventKit) | HA (CalendarEvent) |
|------------------|-------------------|
| `title` | `summary` |
| `notes` | `description` |
| `start_date` / `end_date` | `start` / `end` (ISO 8601, timezone-aware) |
| `is_all_day` | all-day handling per HA calendar API |
| `location` | `location` |
| `url` | `url` (if HA calendar event supports) |
| `last_modified_date` | change detection |
| Recurrence rules | Map RRULE / HA recurrence representation (full fidelity required) |
| Attendees / invitations | Sync status where EventKit exposes; decline/accept stays in Apple if unsupported in HA write path |

### Field mapping — Location

| Apple (MapKit) | HA |
|----------------|-----|
| `latitude`, `longitude` | `device_tracker` lat/long |
| `horizontal_accuracy` | `gps_accuracy` attribute (if available) |
| timestamp | `last_updated` |

### Conflict resolution

**Last-write-wins** per item, comparing Apple `last_modified_date` to HA last-known modification snapshot.

### Loop prevention

Sync engine tags outbound operations with `sync_generation` / `origin: ha_integration` in local state. Changes detected immediately after a self-initiated write are skipped for one poll cycle.

### Deletion

- Apple delete → `todo.remove_item` / calendar delete in HA
- HA delete → `delete_reminder` / `delete_event` via ProviderBridge
- User confirmation not required for sync-driven deletes (mirror behavior); first-time setup docs should warn lists are mirrored

---

## HA REST API surface (V1)

| Operation | HA API |
|-----------|--------|
| Test connection | `GET /api/` |
| List todo entities | `GET /api/states` (filter `domain: todo`) or config entry from prior create |
| Todo read | `todo.get_items` service |
| Todo write | `todo.add_item`, `todo.update_item`, `todo.remove_item` |
| Calendar read | `GET /api/calendars`, `GET /api/calendars/<entity>?start=&end=` |
| Calendar write | Calendar create/update via HA calendar platform services (use HA REST calendar endpoints as documented) |
| Device tracker | `POST /api/states/device_tracker.<id>` or `device_tracker.see` service |
| Sensors | `POST /api/states/<entity_id>` |

Exact HA service names and payloads must be verified against the installed HA version during implementation (target: HA 2025.2+ with todo and calendar APIs).

---

## Persistence

| Data | Location |
|------|----------|
| HA URL, toggles, selected list/calendar IDs, intervals | App settings (`UserDefaults` / existing settings model) |
| HA token | Keychain |
| Sync state (per-item last modified, HA entity mapping, last snapshot hash) | `~/Library/Application Support/AppleBridge/ha-integration-state.json` |

Sync state stores **identifiers and timestamps only** — not reminder/calendar content (Apple remains source of truth for data at rest on device).

---

## Permissions and gating

| HA Integration feature | Required permission | Independent of MCP toggle? |
|------------------------|---------------------|----------------------------|
| Reminders sync | Reminders | Yes |
| Calendar sync | Calendars | Yes |
| Location push | Location | Yes |
| Bridge status | None (server state only) | Yes |

If permission revoked at runtime, pause affected domain and surface status in Integrations tab.

---

## Error handling

| Condition | Behavior |
|-----------|----------|
| HA unreachable | Retry next poll; set `ha_sync_healthy` false; show error in UI |
| 401 Unauthorized | Pause sync; prompt re-entry of token |
| EventKit permission denied | Disable domain; link to Permissions tab |
| ProviderBridge error | Log to usage audit (no payloads); skip item; continue batch |
| Recurrence mapping failure | Log error; skip event; do not partial-write broken recurrence |

---

## Concurrency

- All ProviderBridge calls use existing main-actor dispatch (same as MCP)
- HA sync task runs on Rust tokio runtime; batches Apple work via `call_provider`
- MCP tool calls and HA sync interleave on main actor — acceptable latency; monitor in testing
- Do not hold HA HTTP connections across ProviderBridge calls

---

## Testing strategy

| Layer | Approach |
|-------|----------|
| Reminders diff engine | Rust unit tests with fixture JSON pairs |
| Calendar diff engine | Rust unit tests; recurrence edge cases |
| HA REST client | `wiremock` or axum mock server in Rust tests |
| Loop prevention | Unit test: simulate echo change, assert no second write |
| Swift UI | Swift Testing: checklist selection persists, token masked |
| UniFFI config round-trip | Rust integration test |
| End-to-end | Manual smoke matrix (see below) |

### Manual smoke matrix

1. Enable list → items appear in HA
2. Complete in Reminders → complete in HA
3. Add in HA → appears in Reminders
4. Same three flows for Calendar
5. Location toggle → `device_tracker` updates
6. MCP server off → HA Integration still syncs (ProviderBridge direct)
7. MCP `list_reminders` still returns faithful JSON while sync runs

---

## PRD / conventions amendments

Add to PRD scope (new subsection):

> **Optional integrations:** Apple Bridge may include opt-in integrations that consume ProviderBridge and third-party local APIs (e.g. Home Assistant). Integrations must not alter MCP provider fidelity, bind beyond localhost for MCP, or store Apple user data in a local database.

Add approved Rust dependency: `reqwest` (with `rustls`, JSON) for HA REST client.

---

## Implementation phases

### Phase 1 — Foundation
- PRD/conventions update
- `ha_rest_client` module + connection test
- `ha_integration` config types (UniFFI)
- Sync state file read/write
- Integrations tab shell (connection UI only)

### Phase 2 — Reminders two-way sync
- Reminders diff engine + loop prevention
- Checklist UI for reminder lists
- Auto-create HA `local_todo`
- Status rows + diagnostics

### Phase 3 — Calendar two-way sync
- Calendar diff engine (including recurrence)
- Checklist UI for calendars
- Auto-create/link HA calendar entities

### Phase 4 — Location + status
- Location push toggle + interval
- Bridge status sensors in HA

### Phase 5 — Hardening
- Error UX polish
- Documentation (setup guide in repo docs if requested)
- Manual smoke + `just ci`

---

## Explicit skips (documented)

| Provider | Reason |
|----------|--------|
| Contacts | No HA entity; low automation value |
| Vision | On-demand processing, not state sync |
| MapKit (except location) | Tool-style operations, not entity state |

---

## Open items for implementation plan

1. Confirm HA calendar write API for recurring events on target HA version
2. Decide whether to use HA `local_todo` config flow API or REST-only entity creation
3. Entity naming slug rules (collision handling for duplicate list names)
4. Whether Integrations requires MCP server enabled (recommendation: **no**)

---

## Decision log

| Decision | Choice |
|----------|--------|
| Feature name | HA Integration |
| Sync host | Mac (Apple Bridge app) |
| Reminders direction | Two-way |
| Calendar direction | Two-way (option A) |
| List/calendar selection | User checklist in Mac app |
| HA entity creation | Auto-create on first enable |
| Conflict resolution | Last-write-wins |
| V1 transport to HA | Polling |
| Contacts / Vision | Skip |
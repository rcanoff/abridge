# PR 3b: Search / Filter Reminders — Design Spec

**Date:** 2026-06-28  
**Status:** Approved for implementation  
**Branch:** `feat/pr3b-search-filter-reminders`  
**PRD:** `docs/prd.md` § EventKit Provider (search, filtering)  
**Policy:** Root `AGENTS.md` § Framework fidelity; `docs/conventions.md` § JSON and payloads  
**Predecessor:** PR 3a2 (full read projection)

---

## Summary

Add an MCP tool to search and filter reminders using EventKit predicates plus optional post-fetch text matching. Returns the same full faithful `EKReminder` JSON array as `list_reminders` / `get_reminder`.

---

## MCP surface

| Item | Value |
|------|-------|
| Tool name | `eventkit.reminders.search_reminders` |
| Capability | `eventkit.reminders.search` |
| Provider | `eventkit` |
| Operation | `search_reminders` |

Gated independently from `eventkit.reminders.read`. Enabling search does not imply read tools unless both capabilities are enabled in server config.

---

## Apple APIs

| API | Use |
|-----|-----|
| `EKEventStore.predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` | `completion_status: incomplete`; due-date bounds when `due_date_start` / `due_date_end` set |
| `EKEventStore.predicateForCompletedReminders(withCompletionDateStarting:ending:calendars:)` | `completion_status: completed`; date bounds when set (completion-date range on macOS 26) |
| `EKEventStore.predicateForReminders(in:)` | `completion_status: all` or absent; due-date bounds applied post-fetch on `due_date_components` |
| `EKEventStore.fetchReminders(matching:completion:)` | Async fetch; wrapped by existing `EventKitReminderFetch.waitForCompletion` |

Calendar scope: same as `list_reminders` — optional `list_id` restricts to one reminder list; absent means all reminder calendars.

---

## Input schema

```json
{
  "type": "object",
  "properties": {
    "list_id": { "type": "string" },
    "completion_status": {
      "type": "string",
      "enum": ["incomplete", "completed", "all"]
    },
    "due_date_start": { "type": "string", "format": "date-time" },
    "due_date_end": { "type": "string", "format": "date-time" },
    "query": { "type": "string" }
  }
}
```

All fields optional. Empty object `{}` is valid (all reminders in all lists).

| Field | Semantics |
|-------|-----------|
| `list_id` | `calendar.calendar_identifier` of target list; unknown id → `invalid_arguments` |
| `completion_status` | `incomplete` \| `completed` \| `all`; default `all` when absent |
| `due_date_start` | ISO 8601 inclusive lower bound for EventKit due-date predicate; `null` in JSON treated as absent |
| `due_date_end` | ISO 8601 inclusive upper bound; `null` treated as absent |
| `query` | Case-insensitive substring match against `title` and `notes` **after** EventKit fetch |

### Predicate selection (normative)

1. Resolve `calendars` from `list_id` (or all reminder calendars).
2. If `completion_status == incomplete` → `predicateForIncompleteReminders(withDueDateStarting:ending:calendars:)` (pass due-date bounds when present; nil = open-ended).
3. Else if `completion_status == completed` → `predicateForCompletedReminders(withCompletionDateStarting:ending:calendars:)` (pass date bounds when present).
4. Else → `predicateForReminders(in:)`.

### Post-fetch filters (normative)

Apply in order after `fetchReminders`:

1. **Due date (all)** — when `completion_status` is `all` and `due_date_start` or `due_date_end` is set, retain reminders whose `due_date_components` fall within the inclusive range.
2. **Query** — when `query` is non-empty after trim, retain reminders where trimmed lowercased `query` is a substring of `title` or `notes` (nil title/notes skipped for that field).

No sorting or re-ordering beyond EventKit return order.

---

## Output

JSON **array** of full faithful `EKReminder` objects — identical shape to each element of `list_reminders` and to `get_reminder` (PR 3a2 spec). No wrapper object.

---

## Error cases

| Code | When |
|------|------|
| `permission_denied` | Reminders authorization is not `.fullAccess` |
| `invalid_arguments` | Malformed JSON; wrong types; unknown `list_id`; invalid `completion_status`; unparseable ISO8601 dates; `due_date_start` > `due_date_end` when both set; empty `query` type errors |
| `eventkit_error` | Serialization failure; reminder fetch timeout; other EventKit failures |

Structured error JSON: `{ "code": "<code>", "message": "<human-readable>" }`.

---

## UI / capability catalog

`CapabilityCatalog` entry `eventkit.reminders.search` (`id: search`) → `shipped: true` after implementation.

---

## Non-goals

- Write/update/delete reminders
- Calendar events domain
- Server-side full-text index beyond post-fetch `query`
- Changing `list_reminders` behavior

---

## Test matrix (minimum)

| Layer | Cases |
|-------|-------|
| Rust `tools/mod.rs` | Tool registered; schema; capability gating |
| Rust `mcp_protocol.rs` | `tools/list` includes tool when search enabled; `tools/call` dispatches `search_reminders` |
| Rust `capabilities.rs` | Search in v1 allowlist |
| Swift `EventKitProviderTests` | Filters (completion, due date, list_id, query); faithful output; permission; invalid args |
| Swift `MockEventKitStore` | Predicate seam for incomplete/completed/date-range |

Manual smoke: enable Search capability in Settings, call MCP tool against live Reminders data.
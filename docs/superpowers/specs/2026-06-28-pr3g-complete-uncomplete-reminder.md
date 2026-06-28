# PR 3g — Complete / Uncomplete Reminder

**Date:** 2026-06-28  
**Status:** Implemented  
**Branch:** `feat/pr3g-complete-uncomplete-reminder`  
**PRD:** `docs/prd.md` § EventKit Provider (complete reminders)  
**Policy:** Root `AGENTS.md` § Framework fidelity; `docs/conventions.md` § JSON and payloads  
**Predecessor:** PR 3e (update reminder — `is_completed` field exists but dedicated tools are preferred for completion toggles)

---

## Summary

Add two MCP tools to mark reminders complete or incomplete. Both are gated by a single new capability (`eventkit.reminders.complete`). Fetch by `calendar_item_identifier`, toggle `EKReminder.isCompleted` and `completionDate`, save with `commit: true`, return the same full faithful `EKReminder` JSON shape as `get_reminder`.

---

## MCP surface

| Item | Value |
|------|-------|
| Tool names | `eventkit.reminders.complete_reminder`, `eventkit.reminders.uncomplete_reminder` |
| Capability | `eventkit.reminders.complete` (gates **both** tools) |
| Provider | `eventkit` |
| Operations | `complete_reminder`, `uncomplete_reminder` |

Gated independently from `eventkit.reminders.edit`. Enabling complete does not imply edit unless both capabilities are enabled in server config.

---

## Apple APIs

| API | Use |
|-----|-----|
| `EKEventStore.calendarItem(withIdentifier:)` | Resolve `reminder_id` → `EKReminder` (via existing `EventKitStoreing.fetchReminder(withIdentifier:)`) |
| `EKReminder.isCompleted` | Set `true` on complete, `false` on uncomplete |
| `EKReminder.completionDate` | Set to `Date()` on complete, `nil` on uncomplete |
| `EKEventStore.save(_:commit:)` | Persist with `commit: true` (via existing `saveReminder(_:commit:)`) |

---

## Input schema

Both tools share the same input shape:

```json
{
  "type": "object",
  "properties": {
    "reminder_id": { "type": "string" }
  },
  "required": ["reminder_id"]
}
```

| Field | Semantics |
|-------|-----------|
| `reminder_id` | `EKReminder.calendarItemIdentifier`; required, non-empty after trim; unknown id → `invalid_arguments` |

### Completion semantics (normative)

| Operation | `isCompleted` | `completionDate` |
|-----------|---------------|----------------|
| `complete_reminder` | `true` | `Date()` (server-local instant at save time) |
| `uncomplete_reminder` | `false` | `nil` |

Other reminder fields (title, notes, due date, alarms, recurrence) are left unchanged.

---

## Output

Single faithful `EKReminder` JSON object — identical shape to `get_reminder` / `list_reminders` items. Response includes updated `is_completed` and `completion_date` keys.

---

## Error cases

| Code | When |
|------|------|
| `permission_denied` | Reminders authorization is not `.fullAccess` |
| `invalid_arguments` | Missing `reminder_id`; empty/whitespace `reminder_id`; unknown `reminder_id`; malformed JSON |
| `eventkit_error` | Serialization failure; save failure; other EventKit failures |

Structured error JSON: `{ "code": "<code>", "message": "<human-readable>" }`.

---

## Swift implementation

1. `EventKitProviderComplete.swift` — `completeReminder`, `uncompleteReminder`, shared `setReminderCompletion(isCompleted:)`.
2. Wire `complete_reminder` and `uncomplete_reminder` into `EventKitProvider.handle` (mutation routing).
3. `CapabilityCatalog`: `eventkit.reminders.complete` (`id: complete`) → `shipped: true`.

---

## Rust implementation

1. `EVENTKIT_REMINDERS_COMPLETE` in `capabilities.rs` — add to v1 allowlist.
2. `TOOL_COMPLETE_REMINDER` and `TOOL_UNCOMPLETE_REMINDER` in `tools/mod.rs` with shared input schema and dispatch metadata (both map to `eventkit.reminders.complete` capability).
3. `lists_complete_tools_when_complete_capability_enabled` unit test.
4. Config validation test: `accepts_complete_capability`.
5. MCP protocol integration tests: `tools/list` includes both tools when complete enabled; `tools/call` dispatches each operation.

---

## Authorization

Same gate as other reminder operations: `.fullAccess` required; otherwise `permission_denied`.

---

## Non-goals

- Custom `completion_date` on complete (always set to current instant; use `update_reminder` for explicit dates)
- Batch complete/uncomplete
- Completing recurring reminder instances beyond what EventKit does by default

---

## Test matrix (minimum)

| Layer | Cases |
|-------|-------|
| Rust `tools/mod.rs` | Both tools registered; shared schema; capability gating lists both tools |
| Rust `capabilities.rs` | Complete in v1 allowlist |
| Rust `config_validation.rs` | Accepts `eventkit.reminders.complete` |
| Rust `mcp_protocol.rs` | `tools/list` includes both tools when complete enabled; `tools/call` dispatches `complete_reminder` and `uncomplete_reminder` |
| Swift `EventKitProviderCompleteTests` | Complete/uncomplete success with faithful payload; missing/unknown id; permission denied |
| Swift `EventKitProviderCompleteValidationTests` | Empty `reminder_id` rejected |
| Swift `AppleProviderBridgeTests` | Bridge routes `complete_reminder` and `uncomplete_reminder` |

Manual smoke: enable Complete capability in Settings, call both MCP tools against live Reminders data.
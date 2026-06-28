# PR 3i — Set Reminder Recurrence

**Date:** 2026-06-28  
**Status:** Implemented  
**Branch:** `feat/pr3i-reminder-recurrence`  
**PRD:** `docs/prd.md` § EventKit Provider (recurrence)  
**Policy:** Root `AGENTS.md` § Framework fidelity; `docs/conventions.md` § JSON and payloads  
**Predecessor:** PR 3c (create reminder — `recurrence_rules` deserialization exists; this PR adds a dedicated replace tool)

---

## Summary

Expose a dedicated MCP tool to replace a reminder's recurrence rule list. Fetch by `calendar_item_identifier`, set `EKReminder.recurrenceRules` from the input array (faithful `EKRecurrenceRule` deserialization — same shape as `create_reminder` / `update_reminder`), save with `commit: true`, return the same complete `EKReminder` JSON shape as `get_reminder`.

Pass an empty `recurrence_rules` array to remove all recurrence rules. No separate remove tool — array replacement is the sole mutation surface.

---

## MCP surface

| Item | Value |
|------|-------|
| Tool name | `eventkit.reminders.set_reminder_recurrence` |
| Capability | `eventkit.reminders.recurrence` |
| Provider | `eventkit` |
| Operation | `set_reminder_recurrence` |

Gated independently from `eventkit.reminders.edit` and `eventkit.reminders.create`.

---

## Apple APIs

| API | Use |
|-----|-----|
| `EKEventStore.calendarItem(withIdentifier:)` | Resolve `reminder_id` → `EKReminder` |
| `EKReminder.recurrenceRules` | Full replacement from deserialized input array |
| `EKRecurrenceRule` | Built via `EventKitDeserialization.recurrenceRules` (frequency, interval, end, days/months/weeks, set positions) |
| `EKEventStore.save(_:commit:)` | Persist with `commit: true` |

---

## Input schema

```json
{
  "type": "object",
  "properties": {
    "reminder_id": { "type": "string" },
    "recurrence_rules": { "type": "array" }
  },
  "required": ["reminder_id", "recurrence_rules"]
}
```

**Required**

| Key | Type | Maps to |
|-----|------|---------|
| `reminder_id` | string | `EKReminder.calendarItemIdentifier` |
| `recurrence_rules` | array | `EKReminder.recurrenceRules` — full replacement; `[]` clears all |

Recurrence rule entries use the same faithful `EKRecurrenceRule` JSON objects as `create_reminder` / read projection:

| Key | Type | Notes |
|-----|------|-------|
| `frequency` | string | Required; `daily` \| `weekly` \| `monthly` \| `yearly` |
| `interval` | integer | Optional; default `1` |
| `recurrence_end` | object | Optional; `end_date` (ISO 8601) **or** `occurrence_count` (positive int), not both |
| `days_of_the_week` | array | Optional; objects with `day_of_the_week`, optional `week_number` |
| `days_of_the_month` | array of integers | Optional |
| `days_of_the_year` | array of integers | Optional |
| `months_of_the_year` | array of integers | Optional |
| `weeks_of_the_year` | array of integers | Optional |
| `set_positions` | array of integers | Optional |

Validation errors return `invalid_arguments`. Unknown `reminder_id` returns `invalid_arguments`. `recurrence_rules: null` is rejected (must be an array).

---

## Output

Single faithful `EKReminder` JSON object (identical key set to `get_reminder` / `list_reminders` items), including updated `recurrence_rules`.

---

## Error cases

| Code | When |
|------|------|
| `permission_denied` | Reminders authorization is not `.fullAccess` |
| `invalid_arguments` | Missing `reminder_id` or `recurrence_rules`; empty/whitespace `reminder_id`; unknown `reminder_id`; `recurrence_rules` not an array; invalid frequency; invalid recurrence_end; malformed rule objects |
| `eventkit_error` | Serialization failure; save failure; other EventKit failures |

Structured error JSON: `{ "code": "<code>", "message": "<human-readable>" }`.

---

## Swift implementation

1. `EventKitProviderSetReminderRecurrence.swift` — `setReminderRecurrence`, required-argument parsing, set `reminder.recurrenceRules`, `store.saveReminder(_:commit: true)`.
2. Reuse `EventKitDeserialization.recurrenceRules` (in `EventKitDeserializationRecurrence.swift`).
3. Wire `set_reminder_recurrence` into `EventKitProvider.handle` (mutation routing).
4. `CapabilityCatalog`: `eventkit.reminders.recurrence` (`id: recurrence`) → `shipped: true`.

---

## Rust implementation

1. `EVENTKIT_REMINDERS_RECURRENCE` in `capabilities.rs` — add to v1 allowlist.
2. `TOOL_SET_REMINDER_RECURRENCE` in `tools/mod.rs` with input schema and dispatch metadata.
3. `lists_recurrence_tool_when_recurrence_capability_enabled` unit test.
4. Config validation test: `accepts_recurrence_capability`.
5. MCP protocol integration tests for `tools/list` and `tools/call` dispatch.

---

## Authorization

Same gate as other reminder operations: `.fullAccess` required; otherwise `permission_denied`.

---

## Non-goals

- Partial recurrence merge (use full array replacement)
- Alarm-only tools (PR 3h)
- Recurrence on reminder lists (calendars)

---

## Test matrix (minimum)

| Layer | Cases |
|-------|-------|
| Rust `tools/mod.rs` | Tool registered; schema; capability gating |
| Rust `capabilities.rs` | Recurrence in v1 allowlist |
| Rust `config_validation.rs` | Accepts `eventkit.reminders.recurrence` |
| Rust `mcp_protocol.rs` | `tools/list` includes tool when recurrence enabled; `tools/call` dispatches `set_reminder_recurrence` |
| Swift `EventKitProviderRecurrenceTests` | Set rules → faithful payload; empty array clears rules; missing args; unknown id; permission denied |
| Swift `EventKitRecurrenceValidationTests` | Empty `reminder_id`; invalid frequency; `recurrence_rules: null` |
| Swift `AppleProviderBridgeRecurrenceTests` | Bridge routes `set_reminder_recurrence` |

Manual smoke: enable Recurrence capability in Settings, call MCP tool against live Reminders data.
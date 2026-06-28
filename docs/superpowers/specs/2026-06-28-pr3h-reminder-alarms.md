# PR 3h — Set Reminder Alarms

**Branch:** `feat/pr3h-reminder-alarms`  
**Capability:** `eventkit.reminders.alarms` (new)  
**MCP tool:** `eventkit.reminders.set_reminder_alarms`  
**Provider operation:** `set_reminder_alarms`

## Goal

Expose a dedicated MCP tool to replace a reminder's alarm list. Fetch by `calendar_item_identifier`, set `EKReminder.alarms` from the input array (faithful `EKAlarm` deserialization — same shape as `create_reminder` / `update_reminder`), save with `commit: true`, return the same complete `EKReminder` JSON shape as `get_reminder`.

Pass an empty `alarms` array to remove all alarms. No separate remove tool — array replacement is the sole mutation surface.

## MCP surface

| Item | Value |
|------|-------|
| Tool name | `eventkit.reminders.set_reminder_alarms` |
| Capability | `eventkit.reminders.alarms` |
| Provider | `eventkit` |
| Operation | `set_reminder_alarms` |

### Input (JSON arguments)

**Required**

| Key | Type | Maps to |
|-----|------|---------|
| `reminder_id` | string | `EKReminder.calendarItemIdentifier` (fetch via `EKEventStore.calendarItem(withIdentifier:)`) |
| `alarms` | array | `EKReminder.alarms` — full replacement; `[]` clears all |

Alarm entries use the same faithful `EKAlarm` JSON objects as `create_reminder` (`absolute_date`, `relative_offset`, `proximity`, `email_address`, `structured_location`, etc.).

Validation errors return `invalid_arguments`. Unknown `reminder_id` returns `invalid_arguments`.

### Output

Single faithful `EKReminder` JSON object (identical key set to `get_reminder` / `list_reminders` items).

## Swift implementation

1. `EventKitProviderSetReminderAlarms.swift` — `setReminderAlarms`, required-argument parsing, set `reminder.alarms`, `store.saveReminder(_:commit: true)`.
2. Wire `set_reminder_alarms` into `EventKitProvider.handle`.
3. Mark `eventkit.reminders.alarms` as shipped in `CapabilityCatalog`.

## Rust implementation

1. `EVENTKIT_REMINDERS_ALARMS` in `capabilities.rs` — add to v1 allowlist.
2. `TOOL_SET_REMINDER_ALARMS` in `tools/mod.rs` with input schema and dispatch metadata.
3. MCP protocol integration tests for tools/list and tools/call dispatch.
4. Config validation test for alarms capability.

## Authorization

Same gate as other reminder operations: `.fullAccess` required; otherwise `permission_denied`.

## Out of scope

- Partial alarm merge (use full array replacement)
- Recurrence-only tools (separate PR)

## Verification

- `TZ=UTC just ci` green
- Swift unit tests for set alarms, clear alarms, validation, permission, faithful output shape
- Rust unit + MCP integration tests for capability gating and dispatch
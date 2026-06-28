# PR 3f — Move Reminder to Another List

**Branch:** `feat/pr3f-move-reminder`  
**Capability:** `eventkit.reminders.edit` (reuse existing)  
**MCP tool:** `eventkit.reminders.move_reminder`  
**Provider operation:** `move_reminder`

## Goal

Expose a dedicated MCP tool to move a reminder to another list (calendar). Fetch by `calendar_item_identifier`, set `EKReminder.calendar` to the target `EKCalendar`, save with `commit: true`, return the same complete `EKReminder` JSON shape as `get_reminder`.

## MCP surface

| Item | Value |
|------|-------|
| Tool name | `eventkit.reminders.move_reminder` |
| Capability | `eventkit.reminders.edit` |
| Provider | `eventkit` |
| Operation | `move_reminder` |

### Input (JSON arguments)

**Required**

| Key | Type | Maps to |
|-----|------|---------|
| `reminder_id` | string | `EKReminder.calendarItemIdentifier` (fetch via `EKEventStore.calendarItem(withIdentifier:)`) |
| `calendar_identifier` | string | Target list — `EKReminder.calendar` (resolved via reminder calendars) |

Validation errors return `invalid_arguments`. Unknown `reminder_id` or `calendar_identifier` returns `invalid_arguments`.

### Output

Single faithful `EKReminder` JSON object (identical key set to `get_reminder` / `list_reminders` items).

## Swift implementation

1. `EventKitProviderMove.swift` — `moveReminder`, required-argument parsing, set `reminder.calendar`, `store.saveReminder(_:commit: true)`.
2. Wire `move_reminder` into `EventKitProvider.handle`.

## Rust implementation

1. `TOOL_MOVE_REMINDER` in `tools/mod.rs` with input schema and dispatch metadata (same `eventkit.reminders.edit` capability).
2. MCP protocol integration tests for tools/list and tools/call dispatch.

## Authorization

Same gate as other reminder operations: `.fullAccess` required; otherwise `permission_denied`.

## Out of scope

- Partial field updates (use `update_reminder`)
- Delete, complete-only shortcuts

## Verification

- `TZ=UTC just ci` green
- Swift unit tests for move success, validation, permission, faithful output shape
- Rust unit + MCP integration tests for capability gating and dispatch
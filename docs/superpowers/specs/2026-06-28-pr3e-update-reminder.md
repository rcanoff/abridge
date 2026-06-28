# PR 3e — Update Reminder

**Branch:** `feat/pr3e-update-reminder`  
**Capability:** `eventkit.reminders.edit`  
**MCP tool:** `eventkit.reminders.update_reminder`  
**Provider operation:** `update_reminder`

## Goal

Expose reminder updates through MCP with faithful Apple EventKit mapping. Fetch by `calendar_item_identifier`, apply only fields present in the input, save with `commit: true`, return the same complete `EKReminder` JSON shape as `get_reminder`.

## MCP surface

| Item | Value |
|------|-------|
| Tool name | `eventkit.reminders.update_reminder` |
| Capability | `eventkit.reminders.edit` |
| Provider | `eventkit` |
| Operation | `update_reminder` |

### Input (JSON arguments)

**Required**

| Key | Type | Maps to |
|-----|------|---------|
| `reminder_id` | string | `EKReminder.calendarItemIdentifier` (fetch via `EKEventStore.calendarItem(withIdentifier:)`) |

**Optional** (omit key = leave unchanged; `null` = clear Apple property where applicable)

| Key | Type | Maps to |
|-----|------|---------|
| `calendar_identifier` | string | `EKReminder.calendar` (resolved via reminder calendars) |
| `title` | string | `title` |
| `notes` | string | `notes` |
| `location` | string | `location` |
| `url` | string | `url` |
| `priority` | integer | `priority` (0–9 per EventKit) |
| `due_date_components` | object | `dueDateComponents` |
| `start_date_components` | object | `startDateComponents` |
| `time_zone` | string | `timeZone` (identifier) |
| `is_completed` | boolean | `isCompleted` |
| `completion_date` | ISO 8601 string | `completionDate` |
| `alarms` | array | `alarms` |
| `recurrence_rules` | array | `recurrenceRules` |

Validation errors return `invalid_arguments`. Unknown `reminder_id` or `calendar_identifier` returns `invalid_arguments`.

### Output

Single faithful `EKReminder` JSON object (identical key set to `get_reminder` / `list_reminders` items).

## Swift implementation

1. `EventKitProviderUpdate.swift` — `updateReminder`, argument parsing with present/absent field semantics, property application (reuse `EventKitDeserialization`).
2. Wire `update_reminder` into `EventKitProvider.handle`.
3. Fetch via existing `store.fetchReminder(withIdentifier:)`, mutate, `store.saveReminder(_:commit: true)`.

## Rust implementation

1. `EVENTKIT_REMINDERS_EDIT` constant in `capabilities.rs`; add to v1 allowlist.
2. `TOOL_UPDATE_REMINDER` in `tools/mod.rs` with input schema and dispatch metadata.
3. Config validation + MCP protocol integration tests.

## UI / catalog

`CapabilityCatalog`: edit capability `shipped: true`.

## Authorization

Same gate as other reminder operations: `.fullAccess` required; otherwise `permission_denied`.

## Out of scope

- Delete, complete-only shortcuts (separate PRs)
- Live EventKit permission-dialog CI tests

## Verification

- `TZ=UTC just ci` green
- Swift unit tests for update success, partial update, validation, permission, faithful output shape
- Rust unit + MCP integration tests for capability gating and dispatch
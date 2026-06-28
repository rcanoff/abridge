# PR 3c — Create Reminder

**Branch:** `feat/pr3c-create-reminder`  
**Capability:** `eventkit.reminders.create`  
**MCP tool:** `eventkit.reminders.create_reminder`  
**Provider operation:** `create_reminder`

## Goal

Expose reminder creation through MCP with faithful Apple EventKit mapping. Input keys mirror writable `EKReminder` / `EKCalendarItem` properties (snake_case). Output is the same complete `EKReminder` JSON shape as `get_reminder`.

## MCP surface

| Item | Value |
|------|-------|
| Tool name | `eventkit.reminders.create_reminder` |
| Capability | `eventkit.reminders.create` |
| Provider | `eventkit` |
| Operation | `create_reminder` |

### Input (JSON arguments)

**Required**

| Key | Type | Maps to |
|-----|------|---------|
| `calendar_identifier` | string | `EKReminder.calendar` (resolved via `EKEventStore.calendars(for: .reminder)`) |
| `title` | string | `EKReminder.title` |

**Optional** (omit or `null` = leave Apple default)

| Key | Type | Maps to |
|-----|------|---------|
| `notes` | string | `notes` |
| `location` | string | `location` |
| `url` | string | `url` |
| `priority` | integer | `priority` (0–9 per EventKit) |
| `due_date_components` | object | `dueDateComponents` (same shape as read `due_date_components`) |
| `start_date_components` | object | `startDateComponents` (same shape as read `start_date_components`) |
| `time_zone` | string | `timeZone` (identifier) |
| `is_completed` | boolean | `isCompleted` |
| `completion_date` | ISO 8601 string | `completionDate` |
| `alarms` | array | `alarms` (same element shape as read `alarms`) |
| `recurrence_rules` | array | `recurrenceRules` (same element shape as read `recurrence_rules`) |

Validation errors return `invalid_arguments` with a descriptive message. Unknown `calendar_identifier` returns `invalid_arguments`.

### Output

Single faithful `EKReminder` JSON object (identical key set to `get_reminder` / `list_reminders` items).

## Swift implementation

1. Extend `EventKitStoreing` with `makeReminder()` and `saveReminder(_:commit:)`.
2. `LiveEventKitStore`: `EKReminder(eventStore:)`, set properties, `eventStore.save(_:commit:)`.
3. New `EventKitProviderCreate.swift` (or extension file) for `createReminder` operation and argument parsing.
4. `EventKitDeserialization.swift` for mechanical reverse of serialization helpers (`DateComponents`, alarms, recurrence).
5. Mock / stalled stores implement the new protocol methods.

## Rust implementation

1. `EVENTKIT_REMINDERS_CREATE` constant in `capabilities.rs`; add to v1 allowlist.
2. `TOOL_CREATE_REMINDER` in `tools/mod.rs` with input schema and dispatch metadata.
3. Config validation + MCP protocol integration tests.

## UI / catalog

`CapabilityCatalog`: create capability `shipped: true`.

## Authorization

Same gate as other reminder operations: `.fullAccess` required; otherwise `permission_denied`.

## Out of scope

- Update, delete, complete (separate PRs)
- Live EventKit permission-dialog CI tests

## Verification

- `TZ=UTC just ci` green
- Swift unit tests for create success, validation, permission, faithful output shape
- Rust unit + MCP integration tests for capability gating and dispatch
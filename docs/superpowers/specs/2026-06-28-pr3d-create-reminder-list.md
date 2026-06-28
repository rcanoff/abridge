# PR 3d — Create Reminder List

**Branch:** `feat/pr3d-create-reminder-list`  
**Capability:** `eventkit.reminders.create` (reuse — shared with `create_reminder`)  
**MCP tool:** `eventkit.reminders.create_list`  
**Provider operation:** `create_list`

## Goal

Expose reminder list (calendar) creation through MCP with faithful Apple EventKit mapping. Input keys mirror writable `EKCalendar` properties (snake_case). Output is the same complete `EKCalendar` JSON shape as `list_lists` items.

## MCP surface

| Item | Value |
|------|-------|
| Tool name | `eventkit.reminders.create_list` |
| Capability | `eventkit.reminders.create` |
| Provider | `eventkit` |
| Operation | `create_list` |

### Input (JSON arguments)

**Required**

| Key | Type | Maps to |
|-----|------|---------|
| `title` | string | `EKCalendar.title` |

**Optional** (omit or `null` = Apple default)

| Key | Type | Maps to |
|-----|------|---------|
| `cg_color` | object | `EKCalendar.cgColor` (same shape as read `cg_color`) |
| `source_identifier` | string | `EKCalendar.source` (resolved via `EKEventStore.sources`) |

When `source_identifier` is omitted, use `EKEventStore.defaultCalendarForNewReminders()?.source`, falling back to the first available source.

Validation errors return `invalid_arguments` with a descriptive message. Unknown `source_identifier` returns `invalid_arguments`.

### Output

Single faithful `EKCalendar` JSON object (identical key set to `list_lists` items).

## Swift implementation

1. Extend `EventKitStoreing` with `sources()`, `defaultReminderSource()`, `makeReminderCalendar()`, `saveCalendar(_:commit:)`.
2. `LiveEventKitStore`: `EKCalendar(for: .reminder, eventStore:)`, set properties, `eventStore.saveCalendar(_:commit:)`.
3. New `EventKitProviderCreateList.swift` for `createList` operation and argument parsing.
4. `EventKitDeserializationCalendar.swift` for `cg_color` reverse parsing.
5. Mock / stalled stores implement the new protocol methods.

## Rust implementation

1. Reuse `EVENTKIT_REMINDERS_CREATE` in `capabilities.rs` (no new constant).
2. `TOOL_CREATE_LIST` in `tools/mod.rs` with input schema and dispatch metadata.
3. MCP protocol integration tests for capability gating and dispatch.

## UI / catalog

No catalog change — create capability already `shipped: true` from PR 3c.

## Authorization

Same gate as other reminder operations: `.fullAccess` required; otherwise `permission_denied`.

## Out of scope

- Update, delete list (separate PRs)
- Live EventKit permission-dialog CI tests

## Verification

- `TZ=UTC just ci` green
- Swift unit tests for create success, validation, permission, faithful output shape
- Rust unit + MCP integration tests for capability gating and dispatch
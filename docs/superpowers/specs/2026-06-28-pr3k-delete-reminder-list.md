# PR 3k — Delete Reminder List

**Branch:** `feat/pr3k-delete-reminder-list`  
**Capability:** `eventkit.reminders.delete` (reuse)  
**MCP tool:** `eventkit.reminders.delete_list`  
**Provider operation:** `delete_list`

## Goal

Expose a dedicated MCP tool to delete a reminder list by `calendar_identifier`. Resolve the calendar from reminder calendars, remove via `EKEventStore.removeCalendar(_:commit:)`, return the caller-supplied `calendar_identifier` unchanged (not a calendar projection — the object no longer exists).

## MCP surface

| Item | Value |
|------|-------|
| Tool name | `eventkit.reminders.delete_list` |
| Capability | `eventkit.reminders.delete` |
| Provider | `eventkit` |
| Operation | `delete_list` |

### Input (JSON arguments)

**Required**

| Key | Type | Maps to |
|-----|------|---------|
| `calendar_identifier` | string | `EKCalendar.calendarIdentifier` |

Validation errors return `invalid_arguments`. Unknown `calendar_identifier` returns `invalid_arguments`. Whitespace trimming is used only to reject all-whitespace input; the exact caller-supplied string is preserved for lookup and response.

### Output

Success envelope (not a calendar projection; only the Apple property that identifies the removed list):

```json
{ "calendar_identifier": "<id>" }
```

`calendar_identifier` echoes the exact input string used for lookup. Do not invent fields such as `deleted`.

## Swift implementation

1. Add `removeCalendar(_:commit:)` to `EventKitStoreing` / `LiveEventKitStore` / mocks.
2. `EventKitProviderDeleteList.swift` — `deleteList`, required-argument parsing, `store.removeCalendar(_:commit: true)`.
3. Wire `delete_list` into `EventKitProvider.handle`.
4. Reuse shipped `eventkit.reminders.delete` capability in `CapabilityCatalog` (no change).

## Rust implementation

1. `TOOL_DELETE_LIST` in `tools/mod.rs` with input schema and dispatch metadata (same capability as delete reminder).
2. MCP protocol integration tests for tools/list and tools/call dispatch.

## Authorization

Same gate as other reminder operations: `.fullAccess` required; otherwise `permission_denied`.

## Out of scope

- Batch delete
- Deleting reminders inside the list first (EventKit handles cascade per Apple semantics)

## Verification

- `TZ=UTC just ci` green
- Swift unit tests for delete success, validation, permission, calendar removed from store
- Rust unit + MCP integration tests for capability gating and dispatch
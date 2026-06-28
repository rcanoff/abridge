# PR 3j — Delete Reminder

**Branch:** `feat/pr3j-delete-reminder`  
**Capability:** `eventkit.reminders.delete` (new)  
**MCP tool:** `eventkit.reminders.delete_reminder`  
**Provider operation:** `delete_reminder`

## Goal

Expose a dedicated MCP tool to delete a reminder by `calendar_item_identifier`. Fetch by `reminder_id`, remove via `EKEventStore.remove(_:commit:)`, return the deleted reminder's Apple-faithful `calendar_item_identifier` (not a full reminder projection — the object no longer exists).

## MCP surface

| Item | Value |
|------|-------|
| Tool name | `eventkit.reminders.delete_reminder` |
| Capability | `eventkit.reminders.delete` |
| Provider | `eventkit` |
| Operation | `delete_reminder` |

### Input (JSON arguments)

**Required**

| Key | Type | Maps to |
|-----|------|---------|
| `reminder_id` | string | `EKReminder.calendarItemIdentifier` (fetch via `EKEventStore.calendarItem(withIdentifier:)`) |

Validation errors return `invalid_arguments`. Unknown `reminder_id` returns `invalid_arguments`.

### Output

Success envelope (not a reminder projection; only the Apple property that identifies the removed item):

```json
{ "calendar_item_identifier": "<id>" }
```

`calendar_item_identifier` is taken from `EKReminder.calendarItemIdentifier` before removal. Do not invent fields such as `deleted` or rename to `reminder_id` in the response.

## Swift implementation

1. Add `removeReminder(_:commit:)` to `EventKitStoreing` / `LiveEventKitStore` / mocks.
2. `EventKitProviderDelete.swift` — `deleteReminder`, required-argument parsing, `store.removeReminder(_:commit: true)`.
3. Wire `delete_reminder` into `EventKitProvider.handle`.
4. Mark `eventkit.reminders.delete` as shipped in `CapabilityCatalog`.

## Rust implementation

1. `EVENTKIT_REMINDERS_DELETE` in `capabilities.rs` — add to v1 allowlist.
2. `TOOL_DELETE_REMINDER` in `tools/mod.rs` with input schema and dispatch metadata.
3. MCP protocol integration tests for tools/list and tools/call dispatch.
4. Config validation test for delete capability.

## Authorization

Same gate as other reminder operations: `.fullAccess` required; otherwise `permission_denied`.

## Out of scope

- Batch delete
- Delete reminder list (separate capability)

## Verification

- `TZ=UTC just ci` green
- Swift unit tests for delete success, validation, permission, reminder removed from store
- Rust unit + MCP integration tests for capability gating and dispatch
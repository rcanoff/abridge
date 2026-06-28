# PR 3a1: Reminders Read Enrichment — Design Spec

**Date:** 2026-06-28  
**Status:** Draft (planning)  
**Branch:** `feat/pr3a1-read-enrichment`  
**PRD:** `docs/prd.md` § EventKit / Reminders  
**Predecessor:** PR 3a (`eventkit.reminders.read` — `list_lists`, `list_reminders`)  
**Successor:** PR 3b Create (and later write capabilities)

---

## Summary

Small read-milestone follow-up before write PRs. Enriches the existing **Read** capability with:

1. **`list_id` on every reminder object** returned by `list_reminders` (and the new tool)
2. **`eventkit.reminders.get_reminder`** — fetch one reminder by `reminder_id`
3. **Test coverage gaps** from PR 3a (happy-path Swift provider tests, `list_reminders` / `get_reminder` Rust MCP dispatch)

No new MCP capability toggle, no Settings UI changes, no Calendar work.

---

## Goals

| # | Deliverable |
|---|-------------|
| 1 | Reminder JSON includes `list_id` (EKCalendar `calendarIdentifier`) |
| 2 | Tool `eventkit.reminders.get_reminder` gated by `eventkit.reminders.read` |
| 3 | Swift `EventKitProvider` operation `get_reminder` |
| 4 | Rust tool registry + input schema + MCP integration tests |
| 5 | Swift mapping + provider unit tests (no live EventKit in CI) |
| 6 | Manual smoke: `get_reminder` + `list_reminders` show `list_id` against real data |

## Non-goals

- New capability IDs or Permissions UI changes (Read stays one toggle)
- `include_completed` / date-range / text filters (Search PR)
- Alarms, recurrence, priority, start date, completion date fields (ship with those write PRs or later read pass)
- `get_list` / list CRUD
- Breaking renames of existing fields

---

## Approach

**Selected: Approach 1 — Minimal read enrichment under existing Read capability**

Add one tool + one payload field + tests. Keeps PR reviewable (~1 day).

### Rejected

| Alternative | Reason |
|-------------|--------|
| Fold into PR 3b Create | Write PR should not carry read contract changes; clients need `list_id` / `get_reminder` before create flows stabilize |
| Large read expansion (all EKReminder fields) | Violates small-PR strategy; fields belong with alarms/recurrence caps |
| Separate `eventkit.reminders.get` capability | Over-segments; single-item fetch is clearly read semantics |

---

## Reminder JSON contract (updated)

All read tools that return a reminder use the **same object shape**:

```json
{
  "id": "<calendarItemIdentifier>",
  "list_id": "<calendarIdentifier>",
  "title": "<string>",
  "completed": false,
  "due_date": "2026-06-28T12:00:00Z",
  "notes": "<optional string>"
}
```

| Field | Rules |
|-------|--------|
| `id` | `EKReminder.calendarItemIdentifier` |
| `list_id` | `EKReminder.calendar.calendarIdentifier`; `null` if calendar unset (defensive) |
| `title` | Empty string if nil |
| `completed` | `isCompleted` |
| `due_date` | ISO8601 internet datetime, or `null` |
| `notes` | Omitted when empty; present when non-empty |

**Compatibility:** Additive change. Existing PR 3a clients gain `list_id`; no field removals.

---

## Tools

### Existing: `eventkit.reminders.list_reminders`

- **Change:** Payload items now include `list_id` (and `null` when no calendar).
- **Arguments:** Unchanged — optional `list_id` filter.

### New: `eventkit.reminders.get_reminder`

| Field | Value |
|-------|--------|
| Capability | `eventkit.reminders.read` |
| Dispatch | `provider: "eventkit"`, `operation: "get_reminder"` |
| Arguments | `{ "reminder_id": "<string>" }` — **required** |
| Payload | Single reminder object (same shape as above), JSON object not array |
| Errors | `invalid_arguments` — missing/empty/wrong type `reminder_id`; unknown id; item exists but is not a reminder |

---

## Architecture

```
MCP tools/call (get_reminder | list_reminders)
  → Rust tool registry (read capability)
  → ProviderBridge → EventKitProvider
  → EventKitStoreing.fetchReminder(withIdentifier:)  [new protocol method]
  → EKEventStore.calendarItem(withIdentifier:) cast to EKReminder
  → EventKitReminderMapping.reminderDictionary(from:)
  → ProviderResponse JSON
```

### Test seam

Extend `EventKitStoreing` with `fetchReminder(withIdentifier:) throws -> EKReminder?`.

`MockEventKitStore` cannot construct `EKReminder` without a live `EKEventStore`. For CI:

- Introduce `ReminderRepresentable` protocol in `EventKitReminderMapping.swift`
- `EKReminder` conforms in the same file
- `FakeReminder` struct in `AppleBridgeTests/` conforms for happy-path provider + mapping tests
- `MockEventKitStore` holds `[String: FakeReminder]` keyed by id

`LiveEventKitStore.fetchReminder` uses real EventKit. `MockEventKitStore` returns stored fakes.

---

## Error handling

| Condition | `error_json.code` |
|-----------|-------------------|
| Reminders not authorized | `permission_denied` |
| Missing / invalid `reminder_id` | `invalid_arguments` |
| Unknown `reminder_id` | `invalid_arguments` (`Unknown reminder_id: …`) |
| Calendar item is not a reminder | `invalid_arguments` (`Not a reminder: …`) |
| Serialization failure | `eventkit_error` |

Matches PR 3a patterns (`unknown list_id` → `invalid_arguments`).

---

## Testing

| Area | Minimum |
|------|---------|
| Rust | `tools/list` includes `get_reminder` when read enabled |
| Rust | `tools/call` dispatches `list_reminders` and `get_reminder` to mock provider |
| Rust | `get_reminder` capability_disabled without provider call |
| Swift | `reminderDictionary` includes `list_id` (via `FakeReminder`) |
| Swift | `get_reminder` happy path, unknown id, missing arg, permission denied |
| Swift | `list_reminders` happy path returns `list_id` in JSON |
| Manual | curl/MCP client: list → get by id → verify `list_id` matches list |

Commands: `just lint-rust && just test-rust && just test-swift` (or `just ci`).

---

## Success criteria

- [ ] `list_reminders` items include `list_id`
- [ ] `get_reminder` works E2E with bearer auth + Read capability
- [ ] No new capabilities; Read toggle unchanged
- [ ] All CI checks pass
- [ ] Manual smoke documented in implementation plan

---

## PR sequence context

| PR | Scope |
|----|--------|
| **3a1** (this) | Read enrichment |
| 3b | Create |
| 3c | Edit |
| 3d | Delete |
| 3e | Complete |
| 3f | Alarms |
| 3g | Recurrence |
| 3h | Search |
| — | Calendar (only after full Reminders E2E) |
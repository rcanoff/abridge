# PR 3a2: Full EventKit Read Projection — Design Spec

**Date:** 2026-06-28  
**Status:** Draft (approved direction — implement next)  
**Branch:** `feat/pr3a2-full-read-projection`  
**PRD:** `docs/prd.md` § Thin wrapper / EventKit Provider  
**Policy:** Root `AGENTS.md` § Framework fidelity; `docs/conventions.md` § JSON and payloads  
**Predecessor:** PR 3a1 (minimal read JSON — **legacy debt, replaced here**)  
**Successor:** PR 3b Create

---

## Summary

Replace hand-curated reminder/list JSON with **complete, faithful serializations** of EventKit types on all read tools. Same shape everywhere for the same Apple type. Mechanical encoding only (`snake_case` keys, `null`, ISO dates where Apple uses `Date`).

**Breaking change** for MCP clients on the PR 3a/3a1 field names (`id`, `list_id`, `completed`, flat `due_date`). Intentional — aligns with PRD bridge semantics.

---

## Goals

| # | Deliverable |
|---|-------------|
| 1 | `EKReminder` — exhaustive read projection on `list_reminders` + `get_reminder` |
| 2 | `EKCalendar` (reminder lists) — exhaustive read projection on `list_lists` |
| 3 | Nested types (`EKSource`, `EKAlarm`, `EKRecurrenceRule`, `DateComponents`) serialized faithfully |
| 4 | Remove `ReminderRepresentable` production path — mapping reads `EKReminder` directly |
| 5 | Test fakes mirror **full** production JSON shape (fixture JSON or generated from spec) |
| 6 | Document JSON shape in spec (single source of truth for reviewers) |

## Non-goals

- Write tools (Create PR 3b+)
- Calendar **events** domain (Calendar provider later)
- Search/filter semantics
- Rust tool or capability changes (still `eventkit.reminders.read`)

---

## Serialization rules (normative)

1. **Every** Apple property on the target type that is readable on macOS 26 without side effects must appear in JSON.
2. Key = `snake_case` of Apple property name (`calendarItemIdentifier` → `calendar_item_identifier`).
3. `nil` optional → `null` (never `""` / `0` / `false` as substitute).
4. Nested objects stay nested (`calendar`, `source`, `alarms`, `recurrence_rules`).
5. `Date` → ISO 8601 UTC string with internet date-time format.
6. `DateComponents` → object with set fields (`year`, `month`, `day`, `hour`, `minute`, `second`, `time_zone`, `is_all_day` when derivable).
7. `URL` → string; `CGColor` → hex `#RRGGBB` or documented color object (pick one, document in plan).
8. Enums → lowercase `snake_case` string of Apple enum case (`event`, `reminder`, …).
9. Arrays preserve order Apple returns.
10. **No** omitting keys for “empty” values.

---

## `EKReminder` read shape (exhaustive)

Properties from `EKCalendarItem` + `EKReminder` (macOS EventKit):

| JSON key | Apple source | Notes |
|----------|--------------|-------|
| `calendar_item_identifier` | `calendarItemIdentifier` | |
| `calendar_item_external_identifier` | `calendarItemExternalIdentifier` | `null` if nil |
| `calendar` | `calendar` | Full `EKCalendar` object (below) or `null` |
| `title` | `title` | `null` if nil |
| `location` | `location` | `null` if nil |
| `url` | `url` | absoluteString or `null` |
| `notes` | `notes` | `null` if nil |
| `creation_date` | `creationDate` | ISO8601 or `null` |
| `last_modified_date` | `lastModifiedDate` | ISO8601 or `null` |
| `has_alarms` | `hasAlarms` | bool |
| `has_recurrence_rules` | `hasRecurrenceRules` | bool |
| `has_notes` | `hasNotes` | bool |
| `is_completed` | `isCompleted` | bool |
| `completion_date` | `completionDate` | ISO8601 or `null` |
| `priority` | `priority` | int |
| `due_date_components` | `dueDateComponents` | object or `null` |
| `start_date_components` | `startDateComponents` | object or `null` |
| `alarms` | `alarms` | array of alarm objects or `[]` |
| `recurrence_rules` | `recurrenceRules` | array or `[]` |

### `EKAlarm` element

Serialize all readable `EKAlarm` properties: `absolute_date`, `relative_offset`, `structured_location` (if present), `proximity`, `type`, etc. per Apple API on macOS 26.

### `EKRecurrenceRule` element

Serialize `frequency`, `interval`, `first_day_of_the_week`, `days_of_the_week`, `days_of_the_month`, `days_of_the_year`, `weeks_of_the_year`, `months_of_the_year`, `set_positions`, `end`, etc. per Apple API.

---

## `EKCalendar` read shape (reminder lists)

| JSON key | Apple source |
|----------|--------------|
| `calendar_identifier` | `calendarIdentifier` |
| `title` | `title` |
| `type` | `type` |
| `source` | `source` | nested `EKSource` |
| `color` | `cgColor` | encoded hex |
| `allowed_entity_types` | `allowedEntityTypes` | bitmask → array of entity type strings |
| `allows_content_modifications` | `allowsContentModifications` |
| `is_immutable` | `isImmutable` |
| `is_subscribed` | `isSubscribed` |

### `EKSource` nested

| JSON key | Apple source |
|----------|--------------|
| `source_identifier` | `sourceIdentifier` |
| `title` | `title` |
| `source_type` | `sourceType` |

---

## Tools (unchanged names; changed payloads)

| Tool | Returns |
|------|---------|
| `eventkit.reminders.list_lists` | JSON array of full `EKCalendar` objects |
| `eventkit.reminders.list_reminders` | JSON array of full `EKReminder` objects |
| `eventkit.reminders.get_reminder` | Single full `EKReminder` object |

---

## Implementation approach

1. Replace `EventKitReminderMapping` with `EventKitSerialization` (or expand mapping file) — one function per Apple type: `reminderJSON(from: EKReminder)`, `calendarJSON(from: EKCalendar)`, etc.
2. Delete production use of `ReminderRepresentable` / slim `FakeReminder` — tests use JSON fixture files or `FullReminderFixture` matching complete shape.
3. Update Swift tests to assert required keys exist (golden fixture comparison).
4. No Rust changes except if integration tests assert payload substrings (update expectations).

---

## Migration note (PR 3a → 3a2)

| Old (3a/3a1) | New (3a2) |
|--------------|-----------|
| `id` | `calendar_item_identifier` |
| `list_id` | `calendar.calendar_identifier` |
| `completed` | `is_completed` |
| `due_date` (ISO string) | `due_date_components` (object) |
| `notes` omitted when empty | `notes: null` always present |

---

## Success criteria

- [ ] All read tools return full shapes per tables above
- [ ] Reviewer agent policy passes (no subsetting / renaming in diff)
- [ ] `just ci` green
- [ ] Golden JSON fixture tests for reminder + calendar
- [ ] Manual smoke: list → get returns identical field sets for same reminder

---

## Open items

None — implementation plan follows.
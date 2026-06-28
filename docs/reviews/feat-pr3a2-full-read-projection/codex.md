# Review conversation — feat/pr3a2-full-read-projection
**Agent:** codex
**Base:** main
**Started:** 2026-06-28

> **For the implementer:** Reply under open threads before the next review.
> Use `### Reply · implementer` with **Disposition:** `fixed` | `not-fixed` | `disagree` | `partial` and one line why (+ file/line if fixed).
> Do not edit reviewer messages. Do not renumber threads.

## Run log
| Run | Date | HEAD | Open | Resolved | New |
|-----|------|------|------|----------|-----|
| 1 | 2026-06-28 | 88a877b | 2 | 0 | 2 |
| 2 | 2026-06-28 | 88a877b | 1 | 2 | 1 |
| 3 | 2026-06-28 | 44b90fb | 1 | 3 | 1 |
| 4 | 2026-06-28 | e253471 | 1 | 4 | 1 |
| 5 | 2026-06-28 | e9421cb | 1 | 5 | 1 |
| 6 | 2026-06-28 | 3be176a | 0 | 6 | 0 |

## Thread 1 — Reminder projection omits Apple properties

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitSerialization.swift`
**Skills:** requesting-code-review, swiftui-pro

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `reminderJSONObject(from:)` builds the read payload from `calendarItemJSONObject(from:)` plus reminder-specific keys, and `calendarItemJSONObject(from:)` includes identifiers, calendar, title, location, URL, notes, dates, and `has_*` booleans. The diff does not include serialized `EKCalendarItem.timeZone` or `EKCalendarItem.attendees`.
- **Related diff:** Root `AGENTS.md` now requires “full faithful projection” and forbids “field subsetting”; `docs/conventions.md` says read responses must be complete serializations of Apple framework objects.
- **Issue:** The new serializer still subsets `EKReminder` / inherited `EKCalendarItem` state by omitting Apple properties while exposing related flags like `has_attendees`.
- **Why it matters:** A client can receive `has_attendees: true` but has no faithful serialized attendee objects, and the bridge contract explicitly rejects partial read models for framework objects.
- **Fix:** Extend the reminder projection to include the omitted inherited Apple properties, preserving nesting and using `null` for absent values.

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The uncommitted diff adds `"time_zone": jsonValue(item.timeZone?.identifier)` and `"attendees": (item.attendees ?? []).map(participantJSONObject)` to `calendarItemJSONObject(from:)`, plus participant serialization and test key updates.
- **Note:** The original omitted inherited properties are now represented in the WIP diff.

## Thread 2 — Calendar color key semantically renames cgColor

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitSerialization.swift`
**Skills:** requesting-code-review, swiftui-pro

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `calendarJSONObject(from:)` emits `"color": cgColorHexString(from: calendar.cgColor)`.
- **Related diff:** Root `AGENTS.md` says JSON keys should be snake_case encodings of Apple API names, with renamed semantics forbidden. `docs/conventions.md` repeats that keys should mirror Apple property names and rejects semantic aliases.
- **Issue:** The Apple property is `cgColor`, so the faithful snake_case key is `cg_color`; `color` is a semantic alias.
- **Why it matters:** This branch is specifically tightening framework fidelity, and accepting aliases here reintroduces the old converter-style payload shape.
- **Fix:** Rename the key to `cg_color` and update tests that assert calendar read keys.

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The uncommitted diff changes `"color": cgColorHexString(from: calendar.cgColor)` to `"cg_color": cgColorHexString(from: calendar.cgColor)` and updates `calendarReadKeys` plus nested-calendar expectations from `"color"` to `"cg_color"`.
- **Note:** The semantic alias is removed in the WIP diff.

## Thread 3 — cgColor serialization is lossy and can scrub present values

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitSerialization.swift`
**Skills:** requesting-code-review, swiftui-pro

### Review — run 2 · 2026-06-28 · reviewer
- **Evidence:** `calendarJSONObject(from:)` serializes the Apple `calendar.cgColor` property through `cgColorHexString(from:)`; that helper returns `NSNull()` unless `color.components` exists with at least three components, then emits only `#RRGGBB`.
- **Related diff:** Root `AGENTS.md` allows mechanical serialization of Apple properties and forbids `nil` substitution for absent values, field subsetting, and semantic reshaping. `docs/conventions.md` says nested objects should stay nested and read responses must be complete serializations.
- **Issue:** A non-nil `CGColor` can be serialized as `null` for valid non-RGB component layouts, and the `#RRGGBB` string drops at least alpha/color-space information from the framework value.
- **Why it matters:** This is still a partial projection of an Apple object property: clients cannot distinguish absent `cgColor` from an unsupported present color, and they lose framework data even when serialization succeeds.
- **Fix:** Serialize `cg_color` as a structured object that preserves the available `CGColor` data mechanically, such as color-space name/model when available plus the full components array, using `null` only when `calendar.cgColor` itself is nil.

### Follow-up — run 3 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The current diff replaces the prior hex helper with `cgColorJSONObject(from:)`, returning `NSNull()` only when `color` is nil and otherwise preserving `number_of_components`, `components`, `alpha`, `color_space_name`, and `color_space_model`.
- **Note:** The lossy `#RRGGBB` representation and present-value-to-null path are gone.

## Thread 4 — Recurrence optional arrays are serialized as empty arrays

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitSerialization.swift`
**Skills:** requesting-code-review, swiftui-pro**

### Review — run 3 · 2026-06-28 · reviewer
- **Evidence:** `recurrenceRuleJSONObject(from:)` serializes optional EventKit recurrence properties through helpers: `"days_of_the_week": recurrenceDaysOfWeekArray(from: rule.daysOfTheWeek)`, `"days_of_the_month": numberArray(from: rule.daysOfTheMonth)`, `"days_of_the_year": numberArray(from: rule.daysOfTheYear)`, `"months_of_the_year": numberArray(from: rule.monthsOfTheYear)`, `"weeks_of_the_year": numberArray(from: rule.weeksOfTheYear)`, and `"set_positions": numberArray(from: rule.setPositions)`. The helpers return empty arrays for nil: `numbers?.map(\.intValue) ?? []` and `guard let days else { return [] }`.
- **Related diff:** Root `AGENTS.md` requires `nil` / missing optionals to serialize as JSON `null` and forbids substituting defaults for absent Apple values; `docs/conventions.md` repeats that `nil` maps to `null`.
- **Issue:** These optional Apple properties are scrubbed from `nil` to `[]`, which changes the framework value during serialization.
- **Why it matters:** Clients cannot distinguish “Apple reported no recurrence constraint for this field” from “Apple reported an explicitly empty recurrence list,” violating the branch’s framework-fidelity contract.
- **Fix:** Return `NSNull()` for nil optional recurrence arrays and only emit arrays when the EventKit property is non-nil.

### Follow-up — run 4 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The current diff changes `numberArray(from:)` to `numbers?.map(\.intValue) ?? NSNull()` and `recurrenceDaysOfWeekArray(from:)` to `guard let days else { return NSNull() }`; `EventKitSerializationTests.recurrenceRuleJSONObjectSerializesNilOptionalArraysAsNull` now asserts those keys are `NSNull`.
- **Note:** Nil recurrence arrays now preserve `null` instead of being defaulted to empty arrays.

## Thread 5 — DateComponents calendar is omitted

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitSerialization.swift`
**Skills:** requesting-code-review, swiftui-pro

### Review — run 4 · 2026-06-28 · reviewer
- **Evidence:** `dateComponentsJSONObject(from:)` serializes `year`, `month`, `day`, time fields, week fields, `is_leap_month`, and `time_zone`, but it does not include `DateComponents.calendar`. The same helper is used for `"due_date_components"` and `"start_date_components"` in `reminderJSONObject(from:)`.
- **Related diff:** Root `AGENTS.md` explicitly allows `DateComponents → structured object preserving calendar fields`, and the new framework-fidelity rule forbids field subsetting. `docs/conventions.md` says read responses must be complete serializations of Apple framework objects.
- **Issue:** Reminder date components can carry a calendar, but the serializer drops it while otherwise projecting the `DateComponents` structure.
- **Why it matters:** Clients lose part of the Apple value and cannot reconstruct whether EventKit supplied a calendar with the reminder’s due/start components.
- **Fix:** Add a `calendar` field to the DateComponents JSON object, preserving available calendar identity mechanically, and serialize it as `null` when `components.calendar` is nil.

### Follow-up — run 5 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The current diff adds `"calendar"` to `dateComponentsJSONObject(from:)`, serializing `foundationCalendarJSONObject(from:)` when present and `NSNull()` otherwise; `EventKitSerializationTests.dateComponentsJSONObjectIncludesAllRequiredKeys` also adds `"calendar"` to `dateComponentsReadKeys`.
- **Note:** DateComponents calendar state is now represented.

## Thread 6 — Optional collection properties are scrubbed to empty arrays

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitSerialization.swift`
**Skills:** requesting-code-review, swiftui-pro, swift-testing-pro

### Review — run 5 · 2026-06-28 · reviewer
- **Evidence:** `reminderJSONObject(from:)` emits `"alarms": (reminder.alarms ?? []).map(alarmJSONObject)` and `"recurrence_rules": (reminder.recurrenceRules ?? []).map(recurrenceRuleJSONObject)`. `calendarItemJSONObject(from:)` also emits `"attendees": (item.attendees ?? []).map(participantJSONObject)`. The new test `reminderJSONObjectSerializesAbsentValuesFaithfully` asserts absent attendees become an empty array.
- **Related diff:** Root `AGENTS.md` requires `nil` / missing optional values to serialize as JSON `null` and forbids substituting defaults for absent Apple values; `docs/conventions.md` repeats that `nil` maps to `null`.
- **Issue:** Optional EventKit collection properties are being converted from `nil` to `[]`, which is default substitution rather than mechanical serialization.
- **Why it matters:** Clients cannot distinguish “Apple reported no value for this optional collection” from “Apple reported a present but empty collection,” which violates the framework-fidelity contract this branch introduces.
- **Fix:** Preserve `nil` as `NSNull()` for optional collection properties, and only map to arrays when EventKit returns non-nil arrays. Update the absent-value test so it expects `null` for nil optional collections.

### Follow-up — run 6 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The current diff uses `optionalArrayJSONObject(from:map:)` for `"alarms"`, `"recurrence_rules"`, and `"attendees"`; that helper returns `NSNull()` when the optional array is nil. `reminderJSONObjectSerializesAbsentValuesFaithfully` now expects `NSNull` for attendees and alarms, with recurrence rules checked as either null or an array based on the EventKit value.
- **Note:** Optional collection nils are no longer defaulted to empty arrays.

## Summary
No open findings.

## Verification Note
Reviewed only the provided committed diff, existing context, and inlined skills. I did not run tests, builds, linters, shell commands, or inspect files outside the prompt.
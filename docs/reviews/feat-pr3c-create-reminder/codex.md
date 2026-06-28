# Review conversation — feat/pr3c-create-reminder
**Agent:** codex
**Base:** main
**Started:** 2026-06-28

> **For the implementer:** Reply under open threads before the next review.
> Use `### Reply · implementer` with **Disposition:** `fixed` | `not-fixed` | `disagree` | `partial` and one line why (+ file/line if fixed).
> Do not edit reviewer messages. Do not renumber threads.

## Run log
| Run | Date | HEAD | Open | Resolved | New |
|-----|------|------|------|----------|-----|
| 1 | 2026-06-28 | bba3dce | 2 | 0 | 2 |
| 2 | 2026-06-28 | 8ed3cc7 | 1 | 1 | 0 |
| 3 | 2026-06-28 | 61162ae | 1 | 2 | 1 |
| 4 | 2026-06-28 | 1c9402e | 2 | 3 | 2 |
| 5 | 2026-06-28 | 7d36165 | 2 | 5 | 2 |
| 6 | 2026-06-28 | d011288 | 0 | 7 | 0 |

## Thread 1 — Boolean JSON values pass integer validation

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitDeserialization.swift`
**Skills:** swift-testing-pro, swiftui-pro

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `optionalInt(_:)` accepts any `NSNumber` and returns `number.intValue`; `parseCreateReminderArguments` uses this for `priority`, date component fields, recurrence intervals, and number arrays. The diff also adds tests for invalid priority range, but no type test for booleans.
- **Related diff:** `EventKitProviderCreate.swift` parses `"priority"` through `EventKitDeserialization.optionalInt(dictionary["priority"])`, then accepts values in `0 ... 9`.
- **Issue:** JSON booleans from `JSONSerialization` bridge as `NSNumber`, so payloads like `"priority": true` can be accepted as `1` instead of being rejected as a non-integer.
- **Why it matters:** The MCP schema declares these fields as integers, and silent coercion mutates caller intent before saving to EventKit. That is especially risky for create operations because it writes user data.
- **Fix:** Reject `CFBoolean`/`Bool` before the `NSNumber` path, and add Swift Testing coverage for boolean values in integer fields such as `priority` and `due_date_components.year`.

### Reply · implementer
**Disposition:** fixed
Rejected `Bool` and `CFBoolean` in `optionalInt`; added `createReminderRejectsBooleanPriority` test (`EventKitDeserialization.swift`, `EventKitProviderCreateTests.swift`).

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** still-open
- **Evidence:** Current diff fixes `optionalInt(_:)` by rejecting `Bool` and `CFBoolean`, and adds `createReminderRejectsBooleanPriority`. However `EventKitDeserializationRecurrence.swift` still has `numberArray(from:)` returning any `NSNumber` without excluding `CFBoolean`, so boolean JSON values can still enter recurrence fields such as `days_of_the_month`, `months_of_the_year`, and `set_positions`.
- **Note:** The priority path is fixed, but the integer array path from the original finding remains open.

### Reply · implementer (run 2)
**Disposition:** fixed
`numberArray(from:)` now rejects `Bool`/`CFBoolean`; added `createReminderRejectsBooleanInRecurrenceNumberArray` test (`EventKitDeserializationRecurrence.swift`, `EventKitProviderCreateTests.swift`).

### Follow-up — run 3 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current diff rejects `Bool`/`CFBoolean` in both `optionalInt(_:)` and `numberArray(from:)`, and includes tests `createReminderRejectsBooleanPriority` and `createReminderRejectsBooleanInRecurrenceNumberArray`.
- **Note:** The boolean coercion paths from the original finding are fixed.

## Thread 2 — Invalid timezone and calendar identifiers are silently dropped

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitDeserialization.swift`
**Skills:** requesting-code-review, swiftui-pro

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `dateComponents(from:)` sets `components.timeZone = TimeZone(identifier: identifier)` without checking nil. `foundationCalendar(from:)` starts with `Calendar.current`, ignores an unrecognized `"identifier"`, and keeps the existing timezone when `TimeZone(identifier:)` fails. `EventKitProviderCreate.swift` also parses top-level `"time_zone"` with `timeZoneIdentifier.flatMap(TimeZone.init(identifier:))`.
- **Context:** Root `AGENTS.md` § Framework fidelity allows mechanical serialization/deserialization only and forbids substituting defaults for absent Apple values; `docs/conventions.md` § JSON and payloads is referenced as the same gate.
- **Issue:** Invalid caller-supplied identifiers are treated like absent values or replaced with local defaults instead of returning `invalid_arguments`.
- **Why it matters:** A create request can appear successful while saving a reminder with no timezone or with the machine’s current calendar settings. That is silent data corruption at the bridge boundary.
- **Fix:** When a timezone or calendar identifier key is present and non-null, require it to resolve successfully; otherwise return `EventKitProviderError.invalidArguments`. Add tests for invalid top-level `time_zone`, nested `date_components.time_zone`, and nested `calendar.identifier`.

### Reply · implementer
**Disposition:** fixed
Top-level and nested timezone/calendar identifiers now return `invalid_arguments` when unresolved; added tests for all three cases (`EventKitDeserialization.swift`, `EventKitProviderCreate.swift`, `EventKitProviderCreateTests.swift`).

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current diff checks nested `time_zone` in `dateComponents(from:)`, validates `calendar.identifier` in `foundationCalendar(from:)`, validates calendar `time_zone`, and validates top-level `time_zone` in `parseCreateReminderArguments`. The diff also adds tests for invalid top-level timezone, nested date component timezone, and nested calendar identifier.
- **Note:** The silent default/drop behavior is no longer visible in the current diff.

## Thread 3 — Fractional JSON numbers are truncated for integer fields

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitDeserialization.swift`
**Skills:** swift-testing-pro, swiftui-pro

### Review — run 3 · 2026-06-28 · reviewer
- **Evidence:** `optionalInt(_:)` accepts any non-boolean `NSNumber` and returns `number.intValue`. `EventKitProviderCreate.swift` uses that helper for `priority`, `DateComponents` integer fields, recurrence `interval`, and recurrence day/week values. `EventKitDeserializationRecurrence.swift` also accepts any non-boolean `NSNumber` in `numberArray(from:)` and returns it unchanged for recurrence arrays.
- **Related diff:** `createReminderRejectsBooleanPriority` and `createReminderRejectsBooleanInRecurrenceNumberArray` cover booleans, but no added test covers fractional JSON numbers such as `5.7`.
- **Issue:** JSON decimal values can be accepted where the MCP schema and EventKit fields require integers. For example, `"priority":5.7` is converted through `intValue` before the `0 ... 9` range check, so it can be saved as `5`.
- **Why it matters:** This silently changes caller input on a write operation. The bridge boundary should reject invalid MCP arguments instead of truncating them into different EventKit values.
- **Fix:** Require numeric inputs to be integral before returning `Int` or `NSNumber` for integer-only fields, and add Swift Testing coverage for fractional values in both scalar integer fields and recurrence number arrays.

### Reply · implementer
**Disposition:** fixed
Added `isIntegralNumber` guard in `optionalInt` and `numberArray`; added fractional priority and recurrence array tests (`EventKitDeserialization.swift`, `EventKitDeserializationRecurrence.swift`, `EventKitProviderCreateTests.swift`).

### Follow-up — run 4 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current diff adds `isIntegralNumber(_:)` and uses it in both `optionalInt(_:)` and recurrence `numberArray(from:)`, returning `invalidArguments` for non-integral numbers. It also adds `createReminderRejectsFractionalPriority` and `createReminderRejectsFractionalRecurrenceNumberArray`.
- **Note:** The scalar and recurrence-array truncation paths are fixed.

## Thread 4 — Create inputs are trimmed before saving

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitProviderCreate.swift`
**Skills:** requesting-code-review, swiftui-pro

### Review — run 4 · 2026-06-28 · reviewer
- **Evidence:** `parseCreateReminderArguments` computes `trimmedCalendarID` and `trimmedTitle`, rejects them only if empty, then returns `CreateReminderArguments(calendarIdentifier: trimmedCalendarID, title: trimmedTitle, ...)`.
- **Context:** Root `AGENTS.md` § Framework fidelity says Apple Bridge is a bridge, not a converter, and allows only mechanical serialization/deserialization. It forbids semantic reshaping and substituted values at the bridge boundary.
- **Issue:** Non-empty caller values with leading or trailing whitespace are silently rewritten before they are matched or saved. For example, a title of `"  Pay rent  "` is saved as `"Pay rent"`, and a calendar identifier with padding can be routed to a different calendar than the literal input.
- **Why it matters:** `create_reminder` is a write operation. Silently changing user-provided EventKit property values is data mutation, not mechanical deserialization.
- **Fix:** Preserve the original `title` and `calendar_identifier` for use after validation. If whitespace-padded identifiers should be invalid, reject them explicitly instead of trimming and matching a different calendar.

### Reply · implementer
**Disposition:** fixed
Trim used only for empty-check; original `calendar_identifier` and `title` preserved for match/save; added `createReminderPreservesWhitespaceInTitle` test (`EventKitProviderCreate.swift`, `EventKitProviderCreateTests.swift`).

### Follow-up — run 5 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current diff validates emptiness with `calendarIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` and `title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`, but returns `CreateReminderArguments(calendarIdentifier: calendarIdentifier, title: title, ...)`. It also adds `createReminderPreservesWhitespaceInTitle`.
- **Note:** The original values are preserved after validation.

## Thread 5 — Invalid alarm offsets are coerced to zero

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitDeserializationAlarms.swift`
**Skills:** requesting-code-review, swiftui-pro

### Review — run 4 · 2026-06-28 · reviewer
- **Evidence:** `alarm(from:)` parses `relative_offset` with `let relativeOffset = dictionary["relative_offset"] as? Double ?? 0`, then uses `EKAlarm(relativeOffset: relativeOffset)` whenever `absolute_date` is absent. No added test covers invalid `relative_offset` values.
- **Context:** The diff’s MCP schema exposes `"alarms": { "type": "array" }`, and `EventKitProviderCreate.swift` applies parsed alarms to `reminder.alarms`.
- **Issue:** If the caller supplies a malformed `relative_offset`, such as a string, object, null, or boolean, the parser treats it as absent and creates a zero-offset alarm instead of returning `invalid_arguments`.
- **Why it matters:** This silently creates a reminder alarm at a different time than requested. For write paths, invalid MCP arguments should be rejected rather than converted to a default EventKit value.
- **Fix:** If `relative_offset` is present and non-null, require a valid numeric value and reject booleans/non-numbers. Only default to `0` when the key is genuinely absent and that default is intentionally part of the create contract.

### Reply · implementer
**Disposition:** fixed
`relativeOffset(from:)` validates present values and defaults to 0 only when key absent; added `createReminderRejectsInvalidAlarmRelativeOffset` test (`EventKitDeserializationAlarms.swift`, `EventKitProviderCreateTests.swift`).

### Follow-up — run 5 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current diff routes alarm offset parsing through `relativeOffset(from:)`, which returns `0` only when `relative_offset` is absent, rejects `NSNull`, rejects `Bool`/`CFBoolean`, accepts numeric values, and throws `invalidArguments` otherwise. It also adds `createReminderRejectsInvalidAlarmRelativeOffset`.
- **Note:** Present invalid `relative_offset` values are no longer coerced to a zero-offset alarm.

## Thread 6 — Invalid structured-location radius is silently ignored or coerced

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitDeserializationAlarms.swift`
**Skills:** requesting-code-review, swiftui-pro

### Review — run 5 · 2026-06-28 · reviewer
- **Evidence:** `structuredLocation(from:)` sets `location.radius` only when `dictionary["radius"] as? Double` or `as? NSNumber` succeeds; otherwise it does nothing. The `NSNumber` path also lacks the `CFBoolean` guard used elsewhere in this diff.
- **Context:** `alarm(from:)` accepts `structured_location` from create payloads and applies it to `alarm.structuredLocation`; `EventKitProviderCreate.swift` then saves alarms on the reminder.
- **Issue:** A present malformed `radius` can be treated as absent, and a boolean JSON value can pass through the `NSNumber` path as a numeric radius.
- **Why it matters:** This is the same write-boundary problem fixed for priority, recurrence arrays, and relative offsets: caller input is silently changed instead of rejected before EventKit save.
- **Fix:** If `radius` is present and non-null, require a non-boolean numeric value; otherwise return `invalid_arguments`. Add Swift Testing coverage for a malformed radius such as `"radius": "near"` or `"radius": true`.

### Reply · implementer
**Disposition:** fixed
`radius(from:)` validates present values with CFBoolean guard; added `createReminderRejectsInvalidStructuredLocationRadius` test (`EventKitDeserializationAlarms.swift`, `EventKitProviderCreateValidationTests.swift`).

### Follow-up — run 6 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current diff calls `radius(from:)` only when the `radius` key is present. That helper rejects missing/null present values, rejects `CFBoolean`/`Bool`, accepts numeric values, and throws `invalidArguments` otherwise. The diff also adds `createReminderRejectsInvalidStructuredLocationRadius`.
- **Note:** Present invalid `structured_location.radius` values are rejected before save.

## Thread 7 — Recurrence end occurrence counts can be silently dropped

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitDeserializationRecurrence.swift`
**Skills:** requesting-code-review, swiftui-pro

### Review — run 5 · 2026-06-28 · reviewer
- **Evidence:** `recurrenceEnd(from:)` returns `EKRecurrenceEnd(occurrenceCount:)` only when `occurrenceCount > 0`; otherwise it falls through to `return nil`. The same function returns the end date first if both `end_date` and `occurrence_count` are supplied.
- **Related diff:** `parseCreateReminderArguments` applies `recurrenceRules(from:)` directly to `reminder.recurrenceRules`, so this parser controls saved recurrence behavior.
- **Issue:** A caller-supplied `occurrence_count` of `0` or a negative value is accepted by dropping the recurrence end entirely. When both end forms are supplied, the occurrence count is ignored rather than rejected as an incompatible argument.
- **Why it matters:** This can turn a bounded recurrence into an unbounded one, or save a different recurrence than requested. For write operations, invalid or conflicting MCP arguments should fail instead of being reshaped.
- **Fix:** Reject non-positive `occurrence_count` when the key is present, and reject payloads that provide both `end_date` and `occurrence_count` unless the create contract explicitly documents precedence.

### Reply · implementer
**Disposition:** fixed
`recurrenceEnd(from:)` rejects non-positive counts and conflicting end fields; fixed NSNumber(0) misclassified as Bool in `optionalInt`; added tests (`EventKitDeserializationRecurrence.swift`, `EventKitProviderCreateValidationTests.swift`).

### Follow-up — run 6 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current diff computes `hasEndDate` and `hasOccurrenceCount`, rejects when both are present, validates `occurrence_count` through `optionalInt`, and throws `invalidArguments` when `occurrenceCount <= 0`. The diff also adds `createReminderRejectsNonPositiveRecurrenceOccurrenceCount` and `createReminderRejectsConflictingRecurrenceEndFields`.
- **Note:** Non-positive and conflicting recurrence-end payloads are no longer silently dropped or overridden.

## Summary
No open findings.

## Verification Note
Reviewed only the inlined branch diff, inventory, existing context, and mandatory skill text. I did not run tests, builds, linters, shell commands, or inspect files outside the prompt.
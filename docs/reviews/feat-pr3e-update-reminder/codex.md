# Review conversation — feat/pr3e-update-reminder
**Agent:** codex
**Base:** main
**Started:** 2026-06-28

> **For the implementer:** Reply under open threads before the next review.
> Use `### Reply · implementer` with **Disposition:** `fixed` | `not-fixed` | `disagree` | `partial` and one line why (+ file/line if fixed).
> Do not edit reviewer messages. Do not renumber threads.

## Run log
| Run | Date | HEAD | Open | Resolved | New |
|-----|------|------|------|----------|-----|
| 1 | 2026-06-28 | 7039210 | 2 | 0 | 2 |
| 2 | 2026-06-28 | 106f034 | 1 | 2 | 1 |
| 3 | 2026-06-28 | e2d52eb | 0 | 3 | 0 |

## Thread 1 — Update schema rejects nullable fields the provider supports

**Status:** resolved
**Severity:** bug
**File:** `rust/apple_bridge_core/src/tools/mod.rs`
**Skills:** rust-best-practices, requesting-code-review

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `EventKitProviderUpdateValidationTests.swift` adds `updateReminderClearsNotesWhenNullProvided`, proving `{"notes":null}` is intended and supported by the Swift provider. `EventKitProviderUpdate.swift` parses optional fields with `optionalPresentString`, `optionalPresentURL`, `optionalPresentISO8601Date`, `optionalPresentAlarms`, and `optionalPresentRecurrenceRules`, all of which accept `null`.
- **Related diff:** `rust/apple_bridge_core/src/tools/mod.rs` adds `TOOL_UPDATE_REMINDER` schema where nullable update properties are declared as only `"type": "string"`, `"integer"`, `"boolean"`, `"array"`, or `"object"`; e.g. `"notes": { "type": "string" }`.
- **Context:** Root `AGENTS.md` framework fidelity requires preserving `nil` as JSON `null`, and update semantics need null to clear optional Apple properties.
- **Issue:** The MCP tool schema does not advertise `null` for fields the provider intentionally accepts as nullable. Schema-aware MCP clients may reject or avoid sending `null`, making fields such as `notes`, `location`, `url`, `completion_date`, `alarms`, and `recurrence_rules` impossible to clear through the public tool contract.
- **Why it matters:** The branch exposes update through MCP, so the Rust schema is part of the API. A mismatch between schema and provider behavior breaks faithful Apple property updates for nullable properties.
- **Fix:** For update fields that can be cleared, use a nullable JSON schema form, e.g. `{"type":["string","null"]}` for `notes`, `location`, `url`, `time_zone`, `completion_date`; `{"type":["array","null"]}` for alarms and recurrence rules; and corresponding nullable forms for date component objects if clearing them is supported.

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current `rust/apple_bridge_core/src/tools/mod.rs` declares nullable schema types for the clearable update fields: `notes`, `location`, `url`, `time_zone`, and `completion_date` use `["string","null"]`; date components use `["object","null"]`; `alarms` and `recurrence_rules` use `["array","null"]`.
- **Note:** The originally reported clearable fields are now represented in the MCP schema.

## Thread 2 — `is_completed:null` silently marks reminders incomplete

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitProviderUpdate.swift`
**Skills:** swift-concurrency-pro, requesting-code-review

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `parseUpdateReminderArguments` stores `isCompleted: EventKitDeserialization.optionalPresentBool(dictionary, key: "is_completed")`, so JSON `null` becomes `.present(nil)`. In `applyOptionalDateFields`, the `.present(isCompleted)` branch runs `reminder.isCompleted = isCompleted ?? false`.
- **Related diff:** `EventKitDeserialization.swift` adds `optionalPresentBool`, which explicitly distinguishes absent from present null; `EventKitProviderUpdate.swift` then collapses present null into `false`.
- **Context:** Root `AGENTS.md` framework fidelity forbids substituting `false` for absent or nil values. Even though `EKReminder.isCompleted` is non-optional, accepting `null` and treating it as `false` creates a hidden semantic mutation.
- **Issue:** A client sending `"is_completed": null` will mark a completed reminder incomplete instead of being rejected or requiring an explicit boolean.
- **Why it matters:** This can accidentally change user data from an ambiguous/null payload. For update operations, null should either clear an optional Apple property or be invalid for non-optional fields.
- **Fix:** Reject `null` for `is_completed` with `invalid_arguments`, or make the field non-null at deserialization for update arguments so only explicit `true`/`false` can mutate completion state.

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current `EventKitProviderUpdate.swift` checks `guard let isCompleted else { throw EventKitProviderError.invalidArguments("is_completed must be a boolean") }` before assigning `reminder.isCompleted`. Current `EventKitProviderUpdateValidationTests.swift` adds `updateReminderRejectsNullIsCompleted`.
- **Note:** Present-null completion input is now rejected instead of coerced to `false`.

## Thread 3 — Schema advertises null for fields the provider rejects

**Status:** resolved
**Severity:** bug
**File:** `rust/apple_bridge_core/src/tools/mod.rs`
**Skills:** rust-best-practices, requesting-code-review

### Review — run 2 · 2026-06-28 · reviewer
- **Evidence:** Current `rust/apple_bridge_core/src/tools/mod.rs` declares `"calendar_identifier": { "type": ["string", "null"] }` and `"priority": { "type": ["integer", "null"] }` in the `TOOL_UPDATE_REMINDER` input schema.
- **Related diff:** Current `AppleBridge/Providers/EventKit/EventKitProviderUpdate.swift` rejects both null cases: `calendar_identifier` `.present(nil)` throws `"calendar_identifier must not be empty"`, and `priority` `.present(nil)` throws `"priority must be between 0 and 9"`.
- **Context:** The MCP schema is the public tool contract. It should match provider validation so schema-aware clients do not generate requests that are guaranteed to fail.
- **Issue:** The update tool schema now permits `null` for fields that cannot be cleared through the provider.
- **Why it matters:** Clients using the schema may send `calendar_identifier:null` or `priority:null` expecting a valid clear operation, but the provider returns `invalid_arguments`. That makes the Rust API contract inconsistent with Swift behavior.
- **Fix:** Either remove `null` from the schema for non-clearable fields (`calendar_identifier`, `priority`) or change the Swift provider semantics if those fields are intended to support clearing.

### Follow-up — run 3 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current `rust/apple_bridge_core/src/tools/mod.rs` declares `"calendar_identifier": { "type": "string" }` and `"priority": { "type": "integer" }` in the `TOOL_UPDATE_REMINDER` schema.
- **Note:** The schema no longer advertises `null` for the two provider-rejected fields.

## Summary
No open findings.

## Verification Note
Review was limited to the provided diff, diff inventory, existing code context, AGENTS instructions, and inlined skills. No tests, builds, linters, shell commands, repository reads, or code modifications were performed.
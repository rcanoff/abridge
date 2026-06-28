# Review conversation — feat/pr3b-search-filter-reminders
**Agent:** codex
**Base:** main
**Started:** 2026-06-28

> **For the implementer:** Reply under open threads before the next review.
> Use `### Reply · implementer` with **Disposition:** `fixed` | `not-fixed` | `disagree` | `partial` and one line why (+ file/line if fixed).
> Do not edit reviewer messages. Do not renumber threads.

## Run log
| Run | Date | HEAD | Open | Resolved | New |
|-----|------|------|------|----------|-----|
| 1 | 2026-06-28 | 985f4f5 | 3 | 0 | 3 |
| 2 | 2026-06-28 | 929ce6e | 0 | 3 | 0 |

## Thread 1 — Completed searches filter completion date through due-date arguments

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitProviderSearch.swift`
**Skills:** swiftui-pro, requesting-code-review

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `SearchRemindersArguments` names the range fields `dueDateStart` / `dueDateEnd`, populated from JSON keys `"due_date_start"` and `"due_date_end"`. In `searchPredicate`, the `.completed` branch passes those values to `predicateForCompletedReminders(withCompletionDateStarting:ending:calendars:)`.
- **Related diff:** `rust/apple_bridge_core/src/tools/mod.rs` exposes the schema as `"due_date_start"` / `"due_date_end"` for `eventkit.reminders.search_reminders`, and the tool description says “due-date ... filters”.
- **Issue:** For `completion_status: "completed"`, the API advertises due-date filtering but actually filters by completion date.
- **Why it matters:** A completed reminder due outside the requested due-date window but completed inside it can be returned, and a reminder due inside the window but completed outside it can be omitted. This is also a semantic rename: JSON says due date, but the Apple API property being filtered is completion date.
- **Fix:** Either make completed searches filter by actual `dueDateComponents` after fetching, or expose separate completion-date arguments that accurately map to `completionDate`.

### Reply · implementer
**Disposition:** fixed
Completed predicate no longer receives due-date args; `applyPostFetchFilters` now filters `.completed` by `dueDateComponents` (`EventKitProviderSearch.swift`).

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** In the current diff, the `.completed` branch calls `predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: calendars)`, and `applyPostFetchFilters` applies `dueDate(from: reminder.dueDateComponents)` when due-date args are present for `.completed` or `.all`.
- **Note:** The advertised due-date arguments now filter against reminder due dates for completed searches.

## Thread 2 — Text query filtering adds non-framework search semantics

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitProviderSearch.swift`
**Skills:** requesting-code-review

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `applyPostFetchFilters` lowercases `arguments.query` and returns reminders where `reminder.title` or `reminder.notes` contains the substring.
- **Context:** Root `AGENTS.md` § Framework fidelity says Apple Bridge is a bridge, not a converter; allowed transformations are mechanical serialization only, while derived filtering/sorting/business logic applied to framework data is forbidden. The review gate reiterates that providers must serialize Apple framework objects to JSON, not reshape them.
- **Issue:** The new `query` argument implements app-defined search semantics over selected fields (`title` and `notes`) rather than delegating to an Apple framework predicate or mechanically serializing framework output.
- **Why it matters:** This creates a custom read model behavior that can drift from Apple framework semantics, excludes other searchable Apple properties, and conflicts with the project’s framework fidelity rule.
- **Fix:** Remove `query` from the provider/tool contract unless there is an approved spec exception, or implement only filters directly represented by Apple framework APIs without post-fetch semantic interpretation.

### Reply · implementer
**Disposition:** fixed
Removed `query` from Swift parser/filters, Rust schema, and tests (`EventKitProviderSearch.swift`, `tools/mod.rs`).

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The current `SearchRemindersArguments` contains only `calendarIdentifier`, `completionStatus`, `dueDateStart`, and `dueDateEnd`; `input_schema` for `TOOL_SEARCH_REMINDERS` likewise exposes only `calendar_identifier`, `completion_status`, `due_date_start`, and `due_date_end`.
- **Note:** The custom text query semantics are no longer visible in the diff.

## Thread 3 — New search contract uses `list_id` alias for calendar identifier

**Status:** resolved
**Severity:** bug
**File:** `rust/apple_bridge_core/src/tools/mod.rs`
**Skills:** requesting-code-review

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** The new search schema defines `"list_id": { "type": "string" }`; Swift parses `optionalStringArgument(named: "list_id", ...)` and reports `Unknown list_id`.
- **Context:** Root `AGENTS.md` § Framework fidelity explicitly forbids renamed semantics, including `list_id` for `calendar.calendar_identifier`, unless Apple’s API itself uses that name.
- **Issue:** The new `search_reminders` API adds `list_id` as a semantic alias instead of using Apple-derived naming such as `calendar_identifier` or a nested `calendar.calendar_identifier` shape.
- **Why it matters:** This extends a legacy naming violation into a new endpoint and makes the MCP payload less faithful to EventKit’s model.
- **Fix:** Rename the new search argument and errors to the Apple-derived calendar identifier naming, and keep the schema/Swift parser consistent.

### Reply · implementer
**Disposition:** fixed
Renamed `list_id` → `calendar_identifier` in search schema, parser, and error messages (`tools/mod.rs`, `EventKitProviderSearch.swift`).

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The current Rust schema defines `"calendar_identifier": { "type": "string" }`; Swift parses `optionalStringArgument(named: "calendar_identifier", ...)` and reports `Unknown calendar_identifier`.
- **Note:** The new search endpoint no longer introduces the `list_id` alias.

## Summary
No open findings.

## Verification Note
Reviewed only the inlined current diff, diff inventory, existing code context, AGENTS.md instructions, inlined skills, and the existing conversation. I did not run tests, builds, linters, shell commands, or inspect repository files.
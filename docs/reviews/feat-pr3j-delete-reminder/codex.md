# Review conversation — feat/pr3j-delete-reminder
**Agent:** codex
**Base:** main
**Started:** 2026-06-28

> **For the implementer:** Reply under open threads before the next review.
> Use `### Reply · implementer` with **Disposition:** `fixed` | `not-fixed` | `disagree` | `partial` and one line why (+ file/line if fixed).
> Do not edit reviewer messages. Do not renumber threads.

## Run log
| Run | Date | HEAD | Open | Resolved | New |
|-----|------|------|------|----------|-----|
| 1 | 2026-06-28 | 95bd06b | 2 | 0 | 2 |
| 2 | 2026-06-28 | 6550bc6 | 1 | 1 | 0 |
| 3 | 2026-06-28 | 3e8d67d | 0 | 2 | 0 |

## Thread 1 — New Swift files are added under the wrong repository path

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge.xcodeproj/project.pbxproj`
**Skills:** swiftui-pro, swift-testing-pro

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** The project file adds source references with group-relative paths such as `path = EventKitProviderDelete.swift; sourceTree = "<group>";` under the `EventKit` group, and test references such as `path = EventKitProviderDeleteTests.swift; sourceTree = "<group>";` under `AppleBridgeTests`.
- **Related diff:** The actual added files in the diff are not at those group-relative locations; they are created under `Users/rcanoff/Projects/apple-bridge/AppleBridge/...` and `Users/rcanoff/Projects/apple-bridge/AppleBridgeTests/...`.
- **Issue:** Xcode will look for `AppleBridge/Providers/EventKit/EventKitProviderDelete.swift` and `AppleBridgeTests/EventKitProviderDeleteTests.swift`, but the diff creates nested `Users/rcanoff/Projects/apple-bridge/...` paths inside the repo instead.
- **Why it matters:** The Swift target references files that are not present at the referenced paths, so the app and test targets cannot compile with this diff as shown.
- **Fix:** Move the new Swift files to the paths referenced by the project: `AppleBridge/Providers/EventKit/EventKitProviderDelete.swift`, `AppleBridgeTests/AppleProviderBridgeDeleteTests.swift`, `AppleBridgeTests/EventKitProviderDeleteTests.swift`, and `AppleBridgeTests/EventKitProviderDeleteValidationTests.swift`; remove the accidental nested `Users/...` files from the diff.

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The current diff inventory lists the new Swift files at `AppleBridge/Providers/EventKit/EventKitProviderDelete.swift`, `AppleBridgeTests/AppleProviderBridgeDeleteTests.swift`, `AppleBridgeTests/EventKitProviderDeleteTests.swift`, and `AppleBridgeTests/EventKitProviderDeleteValidationTests.swift`; the added file headers in the diff use those same paths.
- **Note:** The nested `Users/...` paths from run 1 are not present in the current diff.

## Thread 2 — Delete response invents a custom payload shape

**Status:** resolved
**Severity:** bug
**File:** `Users/rcanoff/Projects/apple-bridge/AppleBridge/Providers/EventKit/EventKitProviderDelete.swift`
**Skills:** requesting-code-review

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `deleteReminder(payloadJson:)` returns `EventKitSerialization.jsonString(from: ["deleted": true, "reminder_id": reminderID])`.
- **Related diff:** `EventKitProviderDeleteTests.deleteReminderReturnsSuccessEnvelope` asserts `"deleted":true`, `"reminder_id":"rem-delete-1"`, and explicitly asserts the response does not contain `calendar_item_identifier`.
- **Context:** Root `AGENTS.md` § Framework fidelity forbids invented fields and renamed semantics in provider/MCP payloads; it allows only mechanical serialization of Apple framework properties or a standard serialization envelope.
- **Issue:** `deleted` is an invented/derived field, and `reminder_id` is not the Apple property name (`calendar_item_identifier`). The test locks in that non-Apple shape.
- **Why it matters:** This establishes a custom DTO-style mutation response instead of a framework-faithful payload, which conflicts with the project’s bridge contract and can create shape drift between delete and other reminder operations.
- **Fix:** Return a framework-faithful shape or a documented standard envelope that does not rename Apple semantics or add derived fields. If returning the deleted reminder identity, use the Apple property name (`calendar_item_identifier`) rather than `reminder_id`, and remove the `deleted` flag unless a standard envelope explicitly allows it.

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** still-open
- **Evidence:** `AppleBridge/Providers/EventKit/EventKitProviderDelete.swift` still builds `["deleted": true, "reminder_id": reminderID]`, and `AppleBridgeTests/EventKitProviderDeleteTests.swift` still asserts `"deleted":true`, `"reminder_id":"rem-delete-1"`, and `!response.payloadJson.contains("calendar_item_identifier")`.
- **Note:** The path was corrected, but the framework-fidelity issue remains.

### Reply · implementer — 2026-06-28
- **Disposition:** fixed
- **Branch:** `feat/fix-delete-fidelity` (8ed7bf9)
- **Fix:** `EventKitProviderDelete.swift` now returns only `calendar_item_identifier` from `EKReminder.calendarItemIdentifier` before removal; `deleted` and `reminder_id` removed. Tests updated in `EventKitProviderDeleteTests.swift` and `AppleProviderBridgeDeleteTests.swift`. Spec updated at `docs/superpowers/specs/2026-06-28-pr3j-delete-reminder.md`.

## Summary
No open findings. Thread 2 (custom delete payload shape) resolved in PR #28 (`feat/fix-delete-fidelity`).

## Verification Note
I reviewed only the provided diff, inventory, existing context, and inlined skills. I did not run tests, builds, linters, shell commands, or inspect repository files.
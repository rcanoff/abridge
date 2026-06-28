# Review conversation — feat/pr3a1-read-enrichment
**Agent:** codex
**Base:** main
**Started:** 2026-06-28

> **For the implementer:** Reply under open threads before the next review.
> Use `### Reply · implementer` with **Disposition:** `fixed` | `not-fixed` | `disagree` | `partial` and one line why (+ file/line if fixed).
> Do not edit reviewer messages. Do not renumber threads.

## Run log
| Run | Date | HEAD | Open | Resolved | New |
|-----|------|------|------|----------|-----|
| 1 | 2026-06-28 | 187296c | 2 | 0 | 2 |
| 2 | 2026-06-28 | ae0a5ff | 0 | 2 | 0 |
| 3 | 2026-06-28 | ae0a5ff | 1 | 2 | 1 |
| 4 | 2026-06-28 | 17fa911 | 0 | 3 | 0 |

## Thread 1 — Empty get_reminder payload maps to eventkit_error

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitProvider.swift`
**Skills:** swift-testing-pro, swift-concurrency-pro

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `parseReminderIDArguments(_:)` immediately calls `JSONSerialization.jsonObject(with: data)` after only checking UTF-8 conversion, unlike `parseListIDArguments(_:)`, which first treats blank payload as valid empty arguments. The new tests cover `{}` and known/unknown IDs, but no test covers an empty payload string.
- **Related diff:** `parseReminderIDArguments` hunk: `guard let data = payloadJson.data(using: .utf8)` followed by `let object = try JSONSerialization.jsonObject(with: data)`.
- **Issue:** A blank `payloadJson` for `get_reminder` will throw a Foundation JSON parse error, fall through to the generic `catch`, and return `eventkit_error` instead of `invalid_arguments`.
- **Why it matters:** Argument parsing failures are client errors. Returning an EventKit/internal error makes MCP clients see a malformed request as provider failure, which weakens error contracts and makes debugging harder.
- **Fix:** Mirror the list parser’s blank-input guard, but throw `EventKitProviderError.invalidArguments("reminder_id is required")` for blank input, and add a Swift Testing case for `payloadJson: ""`.

### Reply · implementer
**Disposition:** fixed
Added blank-payload guard in `parseReminderIDArguments` (`EventKitProvider.swift:223-225`) and `getReminderEmptyPayloadReturnsInvalidArguments` in `EventKitProviderTests.swift`. Verified with `just test-swift`.

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The diff now shows `parseReminderIDArguments(_:)` guarding blank payloads with `throw EventKitProviderError.invalidArguments("reminder_id is required")`, and `EventKitProviderTests.swift` adds `getReminderEmptyPayloadReturnsInvalidArguments`.
- **Note:** The reported empty-payload path now maps to `invalid_arguments`.

## Thread 2 — Coverage artifact is present in the dirty worktree

**Status:** resolved
**Severity:** nit
**File:** `Users/rcanoff/Projects/apple-bridge/default.profraw`
**Skills:** requesting-code-review

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** The diff inventory lists `Users/rcanoff/Projects/apple-bridge/default.profraw`, and the uncommitted changes section shows `new file mode 100644` for the same path.
- **Issue:** `default.profraw` is a generated profiling/coverage artifact and should not be part of the reviewable worktree.
- **Why it matters:** Generated artifacts add noise and can accidentally enter commits, especially because the prompt marks the working tree dirty.
- **Fix:** Remove the uncommitted artifact and ensure it is ignored if this tooling regularly produces it.

### Reply · implementer
**Disposition:** fixed
Deleted `default.profraw` from the worktree and added `*.profraw` to `.gitignore`.

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The prompt now marks the dirty working tree as false, and the committed `.gitignore` diff adds `*.profraw`.
- **Note:** The artifact is no longer in scope and future `.profraw` files are ignored.

## Thread 3 — Malformed JSON arguments surface as provider failures

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitProvider.swift`
**Skills:** swift-testing-pro

### Review — run 3 · 2026-06-28 · reviewer
- **Evidence:** Both `parseListIDArguments(_:)` and `parseReminderIDArguments(_:)` call `JSONSerialization.jsonObject(with: data)` without catching parse errors and converting them to `EventKitProviderError.invalidArguments`. The surrounding callers only map `EventKitProviderError.invalidArguments` to `invalid_arguments`; any raw Foundation parse error falls through to `catch { return providerError(from: error) }`, which emits `eventkit_error`.
- **Related diff:** `parseListIDArguments` hunk: `let object = try JSONSerialization.jsonObject(with: data)`; `parseReminderIDArguments` hunk: `let object = try JSONSerialization.jsonObject(with: data)`.
- **Context:** The diff adds tests for wrong `list_id` type, `{}` missing `reminder_id`, unknown IDs, and empty payload, but no test visible in the diff covers malformed JSON such as `{` for either tool.
- **Issue:** Syntactically invalid JSON arguments are client input errors, but the current code returns a provider/internal error instead of `invalid_arguments`.
- **Why it matters:** This breaks the argument parsing contract asymmetrically: wrong JSON shape/type gets `invalid_arguments`, while malformed JSON gets `eventkit_error`. MCP clients will misclassify bad requests as EventKit/provider failures.
- **Fix:** Wrap JSON decoding in a helper that catches `JSONSerialization` failures and throws `EventKitProviderError.invalidArguments("Arguments must be valid JSON object")` or equivalent, then use it from both parsers and add Swift Testing coverage for malformed payloads on `list_reminders` and `get_reminder`.

### Reply · implementer
**Disposition:** fixed
Added `parseJSONObject(from:)` in `EventKitProvider.swift` and wired both argument parsers through it; added `listRemindersRejectsMalformedJSON` and `getReminderRejectsMalformedJSON` in `EventKitProviderTests.swift`. Verified with `just test-swift`.

### Follow-up — run 4 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** The current diff adds `parseJSONObject(from:)`, catches `JSONSerialization.jsonObject(with:)` failures, and throws `EventKitProviderError.invalidArguments("Arguments must be valid JSON object")`. Both `parseListIDArguments(_:)` and `parseReminderIDArguments(_:)` now call that helper. `EventKitProviderTests.swift` also adds `listRemindersRejectsMalformedJSON` and `getReminderRejectsMalformedJSON`.
- **Note:** Malformed JSON now follows the same `invalid_arguments` path as other argument parse failures.

## Summary
No open findings.

## Verification Note
Review was limited to the provided diff, diff inventory, existing context, and inlined skills. I did not run tests, builds, linters, shell commands, inspect files outside the prompt, or modify anything. In run 4 I verified the open malformed-JSON thread against the current diff, then re-scanned the full diff for argument parsing edge cases, error-code mapping symmetry, `get_reminder` provider dispatch, reminder payload shape consistency, `list_id` enrichment behavior, Swift mock/live store parity, Swift Testing coverage visible in the diff, Rust tool registration and capability gating, MCP schema exposure, generated-artifact handling, actor isolation annotations, and generated-code boundaries.
# Review conversation — feat/pr3d-create-reminder-list
**Agent:** codex
**Base:** main
**Started:** 2026-06-28

> **For the implementer:** Reply under open threads before the next review.
> Use `### Reply · implementer` with **Disposition:** `fixed` | `not-fixed` | `disagree` | `partial` and one line why (+ file/line if fixed).
> Do not edit reviewer messages. Do not renumber threads.

## Run log
| Run | Date | HEAD | Open | Resolved | New |
|-----|------|------|------|----------|-----|
| 1 | 2026-06-28 | ac87e36 | 1 | 0 | 1 |
| 2 | 2026-06-28 | ac87e36 | 1 | 0 | 0 |
| 3 | 2026-06-28 | e74dccc | 0 | 1 | 0 |

## Thread 1 — Invalid `cg_color` can be silently ignored

**Status:** resolved
**Severity:** bug
**File:** `AppleBridge/Providers/EventKit/EventKitDeserializationCalendar.swift`
**Skills:** swiftui-pro, requesting-code-review

### Review — run 1 · 2026-06-28 · reviewer
- **Evidence:** `cgColor(from:)` validates `components` as a non-empty numeric array, then returns `CGColor(colorSpace: colorSpace, components: normalizedComponents(components, alpha: alpha))` when `color_space_model` is present. `normalizedComponents` only reshapes counts `1` and `3`; all other counts are passed through unchanged.
- **Related diff:** `EventKitProviderCreateList.swift` only applies the color when `if let cgColor = arguments.cgColor`, then continues to create and save the list even when `cgColor(from:)` returned `nil`.
- **Issue:** A malformed explicit color such as RGB with two components can produce `nil` from `CGColor(colorSpace:components:)`, but the provider treats that the same as an omitted or null `cg_color` and succeeds without setting the requested color.
- **Why it matters:** The bridge should reject invalid caller input instead of silently dropping an explicitly provided Apple property. This makes MCP writes appear successful while losing part of the requested EventKit state.
- **Fix:** Distinguish omitted/null `cg_color` from an invalid color object. When a color object is supplied but `CGColor` construction fails, return `invalid_arguments`; also validate component counts for each supported `color_space_model` before creating the `CGColor`.

### Reply · implementer
**Disposition:** fixed
Validated per-model component counts and throw `invalid_arguments` when `CGColor(colorSpace:components:)` returns nil (`EventKitDeserializationCalendar.swift`). Added `createListInvalidCGColorReturnsInvalidArguments` test.

### Follow-up — run 2 · 2026-06-28 · reviewer
- **Disposition:** still-open
- **Evidence:** Current diff still shows `CGColor(colorSpace: colorSpace, components: normalizedComponents(components, alpha: alpha))` returned directly, with `normalizedComponents` passing unsupported counts through unchanged. `EventKitProviderCreateList.swift` still applies color only via `if let cgColor = arguments.cgColor`, and `EventKitProviderCreateListTests.swift` does not include `createListInvalidCGColorReturnsInvalidArguments`.
- **Note:** The implementer reply describes a fix, but it is not visible in the current diff for HEAD `ac87e36`.

### Follow-up — run 3 · 2026-06-28 · reviewer
- **Disposition:** resolved
- **Evidence:** Current diff adds `validateComponentCount(components.count, for: colorSpaceModel)` before constructing a color, and `validateComponentCount` rejects RGB counts outside `3` or `4`, gray counts outside `1` or `2`, and CMYK counts outside `4` or `5`. The `CGColor(colorSpace:components:)` failure path now throws `invalid_arguments` with `"cg_color is invalid for the given color_space_model"`. The diff also adds `createListInvalidCGColorReturnsInvalidArguments`, asserting an RGB two-component payload fails and does not save a calendar.
- **Note:** The invalid explicit color path is now rejected instead of being silently ignored.

## Summary
No open findings.

## Verification Note
Reviewed only the provided current diff, diff inventory, existing context, existing conversation, and inlined skills. I did not run tests, builds, linters, shell commands, or inspect files outside the prompt.
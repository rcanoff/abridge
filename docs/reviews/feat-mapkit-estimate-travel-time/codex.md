# Review conversation — feat/mapkit-estimate-travel-time
**Agent:** codex
**Base:** main
**Started:** 2026-06-30

> **For the implementer:** Reply under open threads before the next review.
> Use `### Reply · implementer` with **Disposition:** `fixed` | `not-fixed` | `disagree` | `partial` and one line why (+ file/line if fixed).
> Do not edit reviewer messages. Do not renumber threads.

## Run log
| Run | Date | HEAD | Open | Resolved | New |
|-----|------|------|------|----------|-----|
| 1 | 2026-06-30 | da6d996 | 1 | 0 | 1 |
| 2 | 2026-06-30 | c7bd0db | 0 | 1 | 0 |

## Thread 1 — Schema accepts an argument combination the provider rejects

**Status:** resolved
**Severity:** bug
**File:** `rust/apple_bridge_core/src/tools/mod.rs`
**Skills:** rust-best-practices, requesting-code-review

### Review — run 1 · 2026-06-30 · reviewer
- **Evidence:** The Swift provider rejects payloads containing both date fields: `MapKitProviderEstimateTravelTime.swift` throws `invalidArguments("provide departure_date or arrival_date, not both")` when `departureDate != nil, arrivalDate != nil`. The MCP input schema added in `rust/apple_bridge_core/src/tools/mod.rs` exposes both `"departure_date"` and `"arrival_date"` as independent optional properties and only marks `["source", "destination"]` required.
- **Related diff:** `rust/apple_bridge_core/src/tools/mod.rs` adds `TOOL_ESTIMATE_TRAVEL_TIME` schema with both date properties but no mutual-exclusion constraint.
- **Issue:** Tool metadata advertises a payload shape that the provider treats as invalid. MCP clients using `tools/list` can reasonably generate both date fields from the schema and then get a runtime `invalid_arguments` failure.
- **Why it matters:** The Rust server owns MCP routing and config/tool contracts. A schema mismatch is a contract bug, not just validation duplication, because clients rely on schemas to construct valid calls.
- **Fix:** Encode the mutual exclusion in the JSON schema, for example with `oneOf`/`not` constraints that allow neither date, only `departure_date`, or only `arrival_date`, matching the Swift validation.

### Reply · implementer
**Disposition:** fixed — `TOOL_ESTIMATE_TRAVEL_TIME` input schema now adds `route_eta_date_constraints()` `oneOf`/`not` branches so MCP clients cannot advertise both `departure_date` and `arrival_date` (`rust/apple_bridge_core/src/tools/mod.rs`).

### Follow-up — run 2 · 2026-06-30 · reviewer
- **Disposition:** resolved
- **Evidence:** Current diff adds `route_eta_date_constraints()` in `rust/apple_bridge_core/src/tools/mod.rs` with three `oneOf` branches: neither date, only `departure_date`, or only `arrival_date`; the `TOOL_ESTIMATE_TRAVEL_TIME` schema now includes `"oneOf": route_eta_date_constraints().get("oneOf").cloned().expect(...)`.
- **Note:** The schema now matches the Swift provider’s rejection of payloads containing both ETA date fields.

## Summary
No open findings.

## Verification Note
Reviewed only the provided current diff, diff inventory, existing context, and inlined skill requirements. I did not run tests, builds, linters, shell commands, or inspect files outside the prompt.
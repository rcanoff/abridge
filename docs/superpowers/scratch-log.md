# Scratch log — agent feature runs

## EVIDENCE-COLLECTION

- 2026-06-28 — docs commit on `main`: noted PR #29 (`4b1e223`) `parseReminderIDArguments` exact-lookup fix in `docs/reviews/feat-pr3j-delete-reminder/codex.md` (run 4, Thread 2 implementer reply) and `docs/reviews/feat-pr3k-delete-reminder-list/codex.md` (shared parser note). PR #29 returns original `reminder_id` for EventKit lookup; trim only rejects all-whitespace input. `delete_reminder` uses shared parser; `deleteReminderDoesNotTrimReminderIDForLookup` test added.

## FEATURE-10 — Delete reminder list (`feat/pr3k-delete-reminder-list`)

| Step | Status | Notes |
|------|--------|-------|
| FEATURE-10-SPEC | done | `docs/superpowers/specs/2026-06-28-pr3k-delete-reminder-list.md` |
| FEATURE-10-PLAN | done | `docs/superpowers/plans/2026-06-28-pr3k-delete-reminder-list.md` |
| FEATURE-10-BRANCH | done | `feat/pr3k-delete-reminder-list` from `main` @ 52a2bb6 |
| FEATURE-10-TDD-RUST | done | `TOOL_DELETE_LIST`, capability reuse, mcp_protocol tests |
| FEATURE-10-TDD-SWIFT | done | `EventKitProviderDeleteList.swift`, delete list tests, bridge test |
| FEATURE-10-CI | done | `TZ=UTC just ci` green locally |
| FEATURE-10-REVIEW | done | 2 cycles, Codex, 1 open finding (calendar_identifier trim — disagreed; matches delete_reminder/move_reminder) |
| FEATURE-10-PR | done | #27 |
| FEATURE-10-MERGE | done | squash merge → `d7db802` on main |

### Main CI (GitHub Actions)

- Rust CI run `28328593255`: **failure** — billing/spending limit (job never started)
- macOS CI run `28328593259`: **failure** — billing/spending limit (job never started)
- Local `TZ=UTC just ci` passed before merge

## FEATURE-9 — Delete reminder (`feat/pr3j-delete-reminder`)

| Step | Status | Notes |
|------|--------|-------|
| FEATURE-9-SPEC | done | `docs/superpowers/specs/2026-06-28-pr3j-delete-reminder.md` |
| FEATURE-9-PLAN | done | `docs/superpowers/plans/2026-06-28-pr3j-delete-reminder.md` |
| FEATURE-9-BRANCH | done | `feat/pr3j-delete-reminder` from `main` @ 95bd06b |
| FEATURE-9-TDD-RUST | done | `TOOL_DELETE_REMINDER`, capability allowlist, mcp_protocol tests |
| FEATURE-9-TDD-SWIFT | done | `EventKitProviderDelete.swift`, delete + validation tests, bridge test |
| FEATURE-9-CI | done | `TZ=UTC just ci` green locally |
| FEATURE-9-REVIEW | done | 2 cycles, Codex, 1 open finding (success envelope — spec-required, disagreed) |
| FEATURE-9-PR | done | #26 |
| FEATURE-9-MERGE | done | squash merge → `52a2bb6` on main |

### Main CI (GitHub Actions)

- Rust CI run `28328282475`: **failure** — billing/spending limit (job never started)
- macOS CI run `28328282531`: **failure** — billing/spending limit (job never started)
- Local `TZ=UTC just ci` passed before merge

## FEATURE-7 — Set/change/remove reminder alarms (`feat/pr3h-reminder-alarms`)

| Step | Status | Notes |
|------|--------|-------|
| FEATURE-7-SPEC | done | `docs/superpowers/specs/2026-06-28-pr3h-reminder-alarms.md` |
| FEATURE-7-PLAN | done | `docs/superpowers/plans/2026-06-28-pr3h-reminder-alarms.md` |
| FEATURE-7-BRANCH | done | `feat/pr3h-reminder-alarms` from `main` @ ba1a042 |
| FEATURE-7-TDD-RUST | done | `TOOL_SET_REMINDER_ALARMS`, capability allowlist, mcp_protocol tests |
| FEATURE-7-TDD-SWIFT | done | `EventKitProviderSetReminderAlarms.swift`, alarms + validation tests, bridge test |
| FEATURE-7-CI | done | `TZ=UTC just ci` green locally |
| FEATURE-7-REVIEW | done | 2 cycles, Codex, 0 open findings |
| FEATURE-7-PR | done | #24 |
| FEATURE-7-MERGE | done | squash merge → `2c4bd61` on main |

### Main CI (GitHub Actions)

- Rust CI run `28327803102`: **failure** — billing/spending limit (job never started)
- macOS CI run `28327803086`: **failure** — billing/spending limit (job never started)
- Local `TZ=UTC just ci` passed before merge

## FEATURE-5 — Move reminder to another list (`feat/pr3f-move-reminder`)

| Step | Status | Notes |
|------|--------|-------|
| FEATURE-5-SPEC | done | `docs/superpowers/specs/2026-06-28-pr3f-move-reminder.md` |
| FEATURE-5-PLAN | done | `docs/superpowers/plans/2026-06-28-pr3f-move-reminder.md` |
| FEATURE-5-BRANCH | done | `feat/pr3f-move-reminder` from `main` @ 99b51ce |
| FEATURE-5-TDD-RUST | done | `TOOL_MOVE_REMINDER`, schema, mcp_protocol tests |
| FEATURE-5-TDD-SWIFT | done | `EventKitProviderMove.swift`, move + validation tests, bridge test |
| FEATURE-5-CI | done | `TZ=UTC just ci` green locally |
| FEATURE-5-REVIEW | done | 1 cycle, Codex, 0 findings |
| FEATURE-5-PR | done | #22 |
| FEATURE-5-MERGE | done | squash merge → `7d204b6` on main |

### Main CI (GitHub Actions)

- Rust CI run `28327466497`: **failure** — billing/spending limit (job never started)
- macOS CI run `28327466494`: **failure** — billing/spending limit (job never started)
- Local `just ci` passed before merge
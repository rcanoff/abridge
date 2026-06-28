# PR 3a2: Full EventKit Read Projection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace curated PR 3a read JSON with complete faithful `EKReminder` and `EKCalendar` serializations on all read tools.

**Architecture:** Swift-only change in `EventKitSerialization` helpers; mechanical `snake_case` encoding per `docs/superpowers/specs/2026-06-28-pr3a2-full-read-projection-design.md`. Rust tools unchanged.

**Tech Stack:** Swift 6, EventKit, Swift Testing

**Spec:** `docs/superpowers/specs/2026-06-28-pr3a2-full-read-projection-design.md`  
**Branch:** `feat/pr3a2-full-read-projection`

---

## File Map

| File | Action |
|------|--------|
| `AppleBridge/Providers/EventKit/EventKitSerialization.swift` | **Create** — full type serializers |
| `AppleBridge/Providers/EventKit/EventKitReminderMapping.swift` | **Remove** or thin re-export → delete after migration |
| `AppleBridge/Providers/EventKit/EventKitProvider.swift` | Use new serializers |
| `AppleBridgeTests/Fixtures/reminder_read_full.json` | Golden fixture |
| `AppleBridgeTests/Fixtures/calendar_read_full.json` | Golden fixture |
| `AppleBridgeTests/EventKitSerializationTests.swift` | **Create** — golden + key-presence tests |
| `AppleBridgeTests/FakeReminder.swift` | **Remove** — replace with fixture-driven tests |
| `AppleBridgeTests/MockEventKitStore.swift` | Return real-shaped fixture via protocol or stubbed JSON |

---

## Prerequisites

- [ ] Branch from latest `main` (includes merged 3a1)
- [ ] Read root `AGENTS.md` § Framework fidelity
- [ ] Skills: **swift-testing-pro**, **swift-concurrency-pro**

---

### Task 1: Branch

```bash
git checkout main && git pull && git checkout -b feat/pr3a2-full-read-projection
```

---

### Task 2: Golden fixtures + failing tests (TDD)

- [ ] Add `reminder_read_full.json` with **all** keys from spec (nulls explicit)
- [ ] Add `calendar_read_full.json` likewise
- [ ] `EventKitSerializationTests` — `requiredReminderKeysMatchSpec`, `requiredCalendarKeysMatchSpec`
- [ ] Run `just test-swift` — FAIL (serializers missing)

---

### Task 3: Implement serializers

- [ ] `EventKitSerialization.reminderJSONObject(from: EKReminder) -> [String: Any]`
- [ ] `EventKitSerialization.calendarJSONObject(from: EKCalendar) -> [String: Any]`
- [ ] Nested: `source`, `alarm`, `recurrenceRule`, `dateComponents`
- [ ] Wire `EventKitProvider` list/get/list_lists paths
- [ ] Remove `ReminderRepresentable` from production mapping path
- [ ] Run `just test-swift` — PASS

---

### Task 4: Update integration-style provider tests

- [ ] Replace `FakeReminder` usages with fixture-backed mock or minimal `EKReminder` construction where possible
- [ ] Update `EventKitProviderTests` malformed-JSON tests (unchanged behavior)
- [ ] Update `AppleProviderBridgeTests` expectations if payload shape assertions exist

---

### Task 5: CI + review

- [ ] `TZ=UTC just ci`
- [ ] `just review --codex-only` — fidelity gate should pass
- [ ] Manual smoke checklist in spec

---

## Policy commits (can land before or with 3a2)

Tracked separately if desired:

- `AGENTS.md` § Framework fidelity
- `docs/conventions.md` § JSON and payloads
- `AppleBridge/AGENTS.md` provider note
- `local/review/AGENTS.md` reviewer gate (gitignored tooling — user copies locally)
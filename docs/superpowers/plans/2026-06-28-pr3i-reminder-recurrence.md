# Plan — PR 3i Set Reminder Recurrence

**Spec:** `docs/superpowers/specs/2026-06-28-pr3i-reminder-recurrence.md`  
**Branch:** `feat/pr3i-reminder-recurrence`

## Tasks

### 1. Rust tool (TDD)

- [ ] Add `EVENTKIT_REMINDERS_RECURRENCE` to `capabilities.rs` + v1 allowlist
- [ ] Add `TOOL_SET_REMINDER_RECURRENCE` to `tools/mod.rs`, extend `ALL_TOOLS`, `input_schema`
- [ ] `lists_recurrence_tool_when_recurrence_capability_enabled` test
- [ ] `config_validation.rs`: `accepts_recurrence_capability`
- [ ] `mcp_protocol.rs`: tools/list + tools/call dispatch tests

### 2. Swift provider (TDD)

- [ ] `EventKitProviderSetReminderRecurrence.swift` — `setReminderRecurrence`, wire into `handle`
- [ ] Reuse `EventKitDeserialization.recurrenceRules` for rule parsing
- [ ] `CapabilityCatalog`: `recurrence` shipped = true
- [ ] Tests: `EventKitProviderRecurrenceTests`, `EventKitRecurrenceValidationTests`
- [ ] `AppleProviderBridgeRecurrenceTests`: route `set_reminder_recurrence`

### 3. Verify + ship

- [ ] `TZ=UTC just ci`
- [ ] `just review --codex`, triage, fix loop
- [ ] PR squash merge

## Test matrix

| Layer | Test |
|-------|------|
| Swift | set recurrence rules → faithful payload with rules |
| Swift | empty `recurrence_rules` array → clears all rules |
| Swift | missing `reminder_id` → invalid_arguments |
| Swift | missing `recurrence_rules` → invalid_arguments |
| Swift | `recurrence_rules: null` → invalid_arguments |
| Swift | invalid frequency → invalid_arguments |
| Swift | empty/whitespace `reminder_id` → invalid_arguments |
| Swift | unknown reminder_id → invalid_arguments |
| Swift | permission denied |
| Rust | set_reminder_recurrence tool listed when recurrence capability enabled |
| Rust | tools/call dispatches `set_reminder_recurrence` with payload |
| Rust | config accepts `eventkit.reminders.recurrence` |
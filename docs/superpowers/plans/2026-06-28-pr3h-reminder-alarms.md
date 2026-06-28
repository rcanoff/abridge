# Plan — PR 3h Set Reminder Alarms

**Spec:** `docs/superpowers/specs/2026-06-28-pr3h-reminder-alarms.md`  
**Branch:** `feat/pr3h-reminder-alarms`

## Tasks

### 1. Rust tool (TDD)

- [ ] Add `EVENTKIT_REMINDERS_ALARMS` to `capabilities.rs` + v1 allowlist
- [ ] Add `TOOL_SET_REMINDER_ALARMS` to `tools/mod.rs`, extend `ALL_TOOLS`, `input_schema`
- [ ] `lists_alarms_tool_when_alarms_capability_enabled` test
- [ ] `config_validation.rs`: accepts alarms capability
- [ ] `mcp_protocol.rs`: tools/list + tools/call dispatch tests

### 2. Swift provider (TDD)

- [ ] `EventKitProviderSetReminderAlarms.swift` — `setReminderAlarms`, wire into `handle`
- [ ] `CapabilityCatalog`: `alarms` shipped = true
- [ ] Tests: `EventKitProviderSetReminderAlarmsTests`, `EventKitProviderSetReminderAlarmsValidationTests`
- [ ] `AppleProviderBridgeTests`: route `set_reminder_alarms`

### 3. Verify + ship

- [ ] `TZ=UTC just ci`
- [ ] `just review --codex`, triage, fix loop
- [ ] PR squash merge

## Test matrix

| Layer | Test |
|-------|------|
| Swift | set alarms → faithful payload with alarms |
| Swift | empty alarms array → clears alarms |
| Swift | missing `reminder_id` → invalid_arguments |
| Swift | missing `alarms` → invalid_arguments |
| Swift | invalid alarm entry → invalid_arguments |
| Swift | unknown reminder_id → invalid_arguments |
| Swift | permission denied |
| Rust | set_reminder_alarms tool listed when alarms capability enabled |
| Rust | tools/call dispatches `set_reminder_alarms` with payload |
| Rust | config accepts `eventkit.reminders.alarms` |
# Plan — PR 3g Complete / Uncomplete Reminder

**Spec:** `docs/superpowers/specs/2026-06-28-pr3g-complete-uncomplete-reminder.md`  
**Branch:** `feat/pr3g-complete-uncomplete-reminder`

## Tasks

### 1. Rust capability + tools (TDD)

- [ ] Add `EVENTKIT_REMINDERS_COMPLETE` to `capabilities.rs` + v1 allowlist
- [ ] Add `TOOL_COMPLETE_REMINDER` and `TOOL_UNCOMPLETE_REMINDER` to `tools/mod.rs`, extend `ALL_TOOLS`, shared `input_schema`
- [ ] `lists_complete_tools_when_complete_capability_enabled` test
- [ ] `config_validation.rs`: `accepts_complete_capability`
- [ ] `mcp_protocol.rs`: tools/list includes both tools when complete enabled; tools/call dispatch tests for `complete_reminder` and `uncomplete_reminder`

### 2. Swift provider (TDD)

- [ ] `EventKitProviderComplete.swift` — `completeReminder`, `uncompleteReminder`, shared `setReminderCompletion`
- [ ] Wire both operations into `EventKitProvider.handle` (mutation routing)
- [ ] `CapabilityCatalog`: `complete` shipped = true
- [ ] Tests: `EventKitProviderCompleteTests`, `EventKitProviderCompleteValidationTests`
- [ ] `AppleProviderBridgeTests`: route `complete_reminder` and `uncomplete_reminder`

### 3. Verify + ship

- [ ] `TZ=UTC just ci`
- [ ] `just review --codex`, triage, fix loop
- [ ] PR squash merge

## Test matrix

| Layer | Test |
|-------|------|
| Swift | complete → `is_completed: true`, `completion_date` set, other fields unchanged |
| Swift | uncomplete → `is_completed: false`, `completion_date` cleared |
| Swift | missing `reminder_id` → invalid_arguments |
| Swift | empty/whitespace `reminder_id` → invalid_arguments |
| Swift | unknown reminder_id → invalid_arguments |
| Swift | permission denied |
| Rust | both complete tools listed when complete capability enabled |
| Rust | tools/call dispatches `complete_reminder` with payload |
| Rust | tools/call dispatches `uncomplete_reminder` with payload |
| Rust | config accepts `eventkit.reminders.complete` |
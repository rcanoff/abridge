# Plan — PR 3f Move Reminder

**Spec:** `docs/superpowers/specs/2026-06-28-pr3f-move-reminder.md`  
**Branch:** `feat/pr3f-move-reminder`

## Tasks

### 1. Rust tool (TDD)

- [ ] Add `TOOL_MOVE_REMINDER` to `tools/mod.rs`, extend `ALL_TOOLS`, `input_schema`
- [ ] Update `lists_update_tool_when_edit_capability_enabled` test to include move tool
- [ ] `mcp_protocol.rs`: tools/list + tools/call dispatch tests

### 2. Swift provider (TDD)

- [ ] `EventKitProviderMove.swift` — `moveReminder`, wire into `handle`
- [ ] Tests: `EventKitProviderMoveTests`, `EventKitProviderMoveValidationTests`
- [ ] `AppleProviderBridgeTests`: route `move_reminder`

### 3. Verify + ship

- [ ] `TZ=UTC just ci`
- [ ] `just review --codex`, triage, fix loop
- [ ] PR squash merge

## Test matrix

| Layer | Test |
|-------|------|
| Swift | move to target list → faithful payload with new calendar |
| Swift | missing `reminder_id` → invalid_arguments |
| Swift | missing `calendar_identifier` → invalid_arguments |
| Swift | unknown reminder_id → invalid_arguments |
| Swift | unknown calendar_identifier → invalid_arguments |
| Swift | permission denied |
| Rust | move tool listed when edit capability enabled |
| Rust | tools/call dispatches `move_reminder` with payload |
# Plan — PR 3e Update Reminder

**Spec:** `docs/superpowers/specs/2026-06-28-pr3e-update-reminder.md`  
**Branch:** `feat/pr3e-update-reminder`

## Tasks

### 1. Rust capability + tool (TDD)

- [ ] Add `EVENTKIT_REMINDERS_EDIT` to `capabilities.rs` + allowlist test
- [ ] Add `TOOL_UPDATE_REMINDER` to `tools/mod.rs`, extend `ALL_TOOLS`, `input_schema`
- [ ] `config_validation.rs`: accept edit capability
- [ ] `mcp_protocol.rs`: tools/list + tools/call dispatch tests

### 2. Swift provider (TDD)

- [ ] `EventKitDeserialization` — `OptionalField` + `optionalPresent*` helpers
- [ ] `EventKitProviderUpdate.swift` — `updateReminder`, wire into `handle`
- [ ] Tests: `EventKitProviderUpdateTests`, `EventKitProviderUpdateValidationTests`
- [ ] `AppleProviderBridgeTests`: route `update_reminder`

### 3. Catalog

- [ ] `CapabilityCatalog`: edit `shipped: true`
- [ ] `PermissionsStoreTests`: edit shipped requires access

### 4. Verify + ship

- [ ] `TZ=UTC just ci`
- [ ] `just review --codex`, triage, fix loop
- [ ] PR squash merge

## Test matrix

| Layer | Test |
|-------|------|
| Swift | update title only → faithful payload, other fields unchanged |
| Swift | update optional fields (notes, priority, due_date_components) |
| Swift | missing `reminder_id` → invalid_arguments |
| Swift | unknown reminder_id → invalid_arguments |
| Swift | unknown calendar_identifier when moving list → invalid_arguments |
| Swift | permission denied |
| Swift | validation rejects boolean priority, invalid timezone (reuse create patterns) |
| Rust | update tool listed when edit capability enabled |
| Rust | tools/call dispatches `update_reminder` with payload |
| Rust | edit capability accepted in config validation |
# Plan — PR 3c Create Reminder

**Spec:** `docs/superpowers/specs/2026-06-28-pr3c-create-reminder.md`  
**Branch:** `feat/pr3c-create-reminder`

## Tasks

### 1. Rust capability + tool (TDD)

- [ ] Add `EVENTKIT_REMINDERS_CREATE` to `capabilities.rs` + allowlist test
- [ ] Add `TOOL_CREATE_REMINDER` to `tools/mod.rs`, extend `ALL_TOOLS`, `input_schema`
- [ ] `config_validation.rs`: accept create capability
- [ ] `mcp_protocol.rs`: tools/list + tools/call dispatch tests

### 2. Swift store seam (TDD)

- [ ] Extend `EventKitStoreing`: `makeReminder()`, `saveReminder(_:commit:)`
- [ ] Implement in `LiveEventKitStore`, `MockEventKitStore`, `StalledEventKitStore`

### 3. Swift provider (TDD)

- [ ] `EventKitDeserialization.swift` — parse date components, alarms, recurrence from JSON
- [ ] `EventKitProviderCreate.swift` — `createReminder`, wire into `handle`
- [ ] Tests in `EventKitProviderTests.swift`

### 4. Catalog

- [ ] `CapabilityCatalog`: create `shipped: true`

### 5. Verify + ship

- [ ] `TZ=UTC just ci`
- [ ] `just review --codex`, triage, fix loop
- [ ] PR squash merge

## Test matrix

| Layer | Test |
|-------|------|
| Swift | create with required fields → faithful payload |
| Swift | missing `calendar_identifier` / `title` → invalid_arguments |
| Swift | unknown calendar → invalid_arguments |
| Swift | permission denied |
| Swift | optional notes, priority, due_date_components applied |
| Rust | create tool listed when capability enabled |
| Rust | tools/call dispatches `create_reminder` with payload |
| Rust | capability disabled → no provider call |
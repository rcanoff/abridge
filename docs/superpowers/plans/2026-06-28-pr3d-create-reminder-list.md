# Plan — PR 3d Create Reminder List

**Spec:** `docs/superpowers/specs/2026-06-28-pr3d-create-reminder-list.md`  
**Branch:** `feat/pr3d-create-reminder-list`

## Tasks

### 1. Rust tool (TDD)

- [ ] Add `TOOL_CREATE_LIST` to `tools/mod.rs`, extend `ALL_TOOLS`, `input_schema`
- [ ] Update `lists_create_tool_when_create_capability_enabled` for both create tools
- [ ] `mcp_protocol.rs`: tools/list + tools/call dispatch tests

### 2. Swift store seam (TDD)

- [ ] Extend `EventKitStoreing`: `sources()`, `defaultReminderSource()`, `makeReminderCalendar()`, `saveCalendar(_:commit:)`
- [ ] Implement in `LiveEventKitStore`, `MockEventKitStore`, `StalledEventKitStore`

### 3. Swift provider (TDD)

- [ ] `EventKitDeserializationCalendar.swift` — parse `cg_color` from JSON
- [ ] `EventKitProviderCreateList.swift` — `createList`, wire into `handle`
- [ ] Tests in `EventKitProviderCreateListTests.swift`

### 4. Verify + ship

- [ ] `TZ=UTC just ci`
- [ ] `just review --codex`, triage, fix loop
- [ ] PR squash merge

## Test matrix

| Layer | Test |
|-------|------|
| Swift | create with required fields → faithful payload |
| Swift | missing `title` → invalid_arguments |
| Swift | unknown `source_identifier` → invalid_arguments |
| Swift | permission denied |
| Swift | optional `cg_color`, `source_identifier` applied |
| Rust | create_list tool listed when create capability enabled |
| Rust | tools/call dispatches `create_list` with payload |
| Rust | capability disabled → no provider call |
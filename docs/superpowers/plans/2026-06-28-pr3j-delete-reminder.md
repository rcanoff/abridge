# Plan — PR 3j Delete Reminder

**Branch:** `feat/pr3j-delete-reminder`  
**Spec:** `docs/superpowers/specs/2026-06-28-pr3j-delete-reminder.md`

## Tasks

### 1. Rust capability + tool registry (TDD)

- [ ] Add `EVENTKIT_REMINDERS_DELETE` to `capabilities.rs` and v1 allowlist
- [ ] Add `TOOL_DELETE_REMINDER` to `tools/mod.rs` (schema, ALL_TOOLS, unit test)
- [ ] Add `accepts_delete_capability` to `config_validation.rs`
- [ ] Add MCP protocol tests: tools/list gating + tools/call dispatch

### 2. Swift provider (TDD)

- [ ] Add `removeReminder(_:commit:)` to `EventKitStoreing`, `LiveEventKitStore`, `MockEventKitStore`, `StalledEventKitStore`
- [ ] Create `EventKitProviderDelete.swift`
- [ ] Wire `delete_reminder` in `EventKitProvider.handle`
- [ ] Mark delete capability `shipped: true` in `CapabilityCatalog`
- [ ] Tests: `EventKitProviderDeleteTests`, `EventKitProviderDeleteValidationTests`, bridge routing test

### 3. Verification + ship

- [ ] `TZ=UTC just ci`
- [ ] `just review` (0 open findings)
- [ ] Open PR, squash merge to main
- [ ] Log FEATURE-9-* in scratch log
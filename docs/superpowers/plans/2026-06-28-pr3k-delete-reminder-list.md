# Plan — PR 3k Delete Reminder List

**Branch:** `feat/pr3k-delete-reminder-list`  
**Spec:** `docs/superpowers/specs/2026-06-28-pr3k-delete-reminder-list.md`

## Tasks

### 1. Rust tool registry (TDD)

- [ ] Add `TOOL_DELETE_LIST` to `tools/mod.rs` (schema, ALL_TOOLS, unit test)
- [ ] Add MCP protocol tests: tools/list gating + tools/call dispatch

### 2. Swift provider (TDD)

- [ ] Add `removeCalendar(_:commit:)` to `EventKitStoreing`, `LiveEventKitStore`, `MockEventKitStore`, `StalledEventKitStore`
- [ ] Add `parseCalendarIdentifierArguments` to `EventKitProvider`
- [ ] Create `EventKitProviderDeleteList.swift`
- [ ] Wire `delete_list` in `EventKitProvider.handle`
- [ ] Tests: `EventKitProviderDeleteListTests`, `EventKitProviderDeleteListValidationTests`, bridge routing test

### 3. Verification + ship

- [ ] `TZ=UTC just ci`
- [ ] `just review` (0 open findings)
- [ ] Open PR, squash merge to main
- [ ] Log FEATURE-10-* in scratch log
# PR 3b: Search / Filter Reminders — Implementation Plan

> **For agentic workers:** Use TDD — failing tests before implementation. Run `TZ=UTC just ci` before commit.

**Goal:** Expose `eventkit.reminders.search_reminders` MCP tool with EventKit predicate-based filtering and optional post-fetch text search.

**Architecture:** Rust registers tool + capability gate; Swift `EventKitProvider` implements `search_reminders` via extended `EventKitStoreing` predicate seam.

**Tech Stack:** Rust 2024, Swift 6, EventKit, Swift Testing

**Spec:** `docs/superpowers/specs/2026-06-28-pr3b-search-filter-reminders.md`  
**Branch:** `feat/pr3b-search-filter-reminders`

---

## File Map

| File | Action |
|------|--------|
| `rust/apple_bridge_core/src/capabilities.rs` | Add `EVENTKIT_REMINDERS_SEARCH` + allowlist |
| `rust/apple_bridge_core/src/tools/mod.rs` | Add `TOOL_SEARCH_REMINDERS`, schema, tests |
| `rust/apple_bridge_core/tests/mcp_protocol.rs` | tools/list + tools/call integration tests |
| `rust/apple_bridge_core/tests/config_validation.rs` | Accept search capability |
| `AppleBridge/Providers/EventKit/EventKitProvider.swift` | Protocol + live + `search_reminders` |
| `AppleBridgeTests/MockEventKitStore.swift` | Predicate methods + filter behavior |
| `AppleBridgeTests/StalledEventKitStore.swift` | Stub new protocol methods |
| `AppleBridgeTests/EventKitProviderTests.swift` | Search/filter/error tests |
| `AppleBridge/Models/CapabilityCatalog.swift` | `search` shipped: true |

---

## Task 1: Branch ✓

```bash
git checkout main && git pull
git checkout -b feat/pr3b-search-filter-reminders
```

---

## Task 2: Failing tests (TDD)

- [ ] Rust unit: `capabilities` accepts search id
- [ ] Rust unit: `tools_for_capabilities` includes search tool when search enabled
- [ ] Rust integration: `mcp_tools_list_includes_search_reminders`
- [ ] Rust integration: `tools_call_dispatches_search_reminders`
- [ ] Swift: `searchRemindersFiltersByCompletionStatus`
- [ ] Swift: `searchRemindersFiltersByQuery`
- [ ] Swift: `searchRemindersRejectsInvalidCompletionStatus`
- [ ] Run tests — FAIL (not implemented)

---

## Task 3: Rust implementation

- [ ] `capabilities.rs` — constant + `is_allowed_in_v1`
- [ ] `tools/mod.rs` — tool definition + input schema
- [ ] Run `just test-rust` — PASS for Rust tests

---

## Task 4: Swift implementation

- [ ] Extend `EventKitStoreing` with incomplete/completed/due-date predicates
- [ ] `LiveEventKitStore` — wire `EKEventStore` APIs
- [ ] `MockEventKitStore` / `StalledEventKitStore` — test seams
- [ ] `EventKitProvider.searchReminders` — parse args, build predicate, post-filter, serialize
- [ ] `CapabilityCatalog` — search shipped
- [ ] Run `just test-swift` — PASS

---

## Task 5: Verification

```bash
TZ=UTC just ci
```

---

## Task 6: Commit

```
feat: add search_reminders MCP tool for EventKit reminders
```
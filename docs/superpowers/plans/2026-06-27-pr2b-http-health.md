# PR 2b: HTTP + `/health` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace stub `ServerHandle` lifecycle with real HTTP bind, `GET /health`, and graceful shutdown.

**Architecture:** Tokio runtime owned by `ServerHandle`; axum router in `http.rs`; oneshot graceful shutdown; sync UniFFI `start`/`stop` use `runtime.block_on`. No auth, no Swift changes.

**Tech Stack:** axum 0.8, tokio, serde_json (existing deps)

**Spec:** `docs/superpowers/specs/2026-06-27-pr2-mcp-server-design.md` § PR 2b  
**Branch:** `feat/pr2b-http-health`

---

## File Map

| File | Responsibility |
|------|----------------|
| `src/error.rs` | Add `BindFailed` variant |
| `src/http.rs` | Axum router + `/health` handler |
| `src/server.rs` | Runtime, bind, spawn, graceful shutdown |
| `src/lib.rs` | `mod http` |
| `tests/support/port.rs` | `free_port()`, HTTP GET helper |
| `tests/http_health.rs` | Integration tests |
| `tests/server_lifecycle.rs` | Use `free_port()` to avoid bind conflicts |

---

### Task 1: BindFailed error (TDD)

- [ ] Failing test in `tests/error_display.rs`
- [ ] Add `BindFailed { message }` to `error.rs`

### Task 2: HTTP router

- [ ] Create `http.rs` with `router()` and `GET /health` → `{"ok":true}`
- [ ] Wire `mod http` in `lib.rs`

### Task 3: ServerHandle HTTP lifecycle (TDD)

- [ ] Update `server.rs`: runtime in `create_server`, real bind/shutdown in `start`/`stop`
- [ ] Update `server_lifecycle.rs` to use `free_port()`

### Task 4: Integration tests

- [ ] `tests/http_health.rs`: health 200, port release, bind failure
- [ ] `tests/support/port.rs` helpers

### Task 5: Verification

- [ ] `just lint-rust && just test-rust`
- [ ] No Swift changes in diff
# AGENTS.md — rust/

Scoped rules for `abridge_core`. Root `AGENTS.md` still applies.

## Required skills

When **rust-best-practices** is installed, read it before writing or reviewing Rust in this directory.

## Overrides (mandatory)

These supersede **rust-best-practices** when that skill is installed, and they supersede generic Rust advice. `docs/conventions.md` is canonical when this file and the skill disagree.

### Errors

- Use **`thiserror` only** — do not add `anyhow` (this crate is a `staticlib` exposed via UniFFI, not a standalone binary).
- Expose errors as **`CoreError`** with `#[derive(uniffi::Error)]`.
- Return `Result<T, CoreError>` on all user-input and external-data paths.
- Exception: Rust-native providers for Apple apps without a public framework may return provider-local typed errors inside Rust (`NotesError`), without UniFFI error exports.
- Never `unwrap()` / `expect()` on UniFFI-reachable paths — panics abort the app.

### UniFFI

- Proc-macro mode only — no UDL files.
- Re-export the public FFI surface from `lib.rs`.
- `ProviderBridge: Send + Sync` via `#[uniffi::export(callback_interface)]`.
- Follow `docs/conventions.md` for Record/Enum/Object attributes.
- Treat `lib.rs` exports as a stable cross-language contract; prefer additive changes and review removals or signature changes as FFI/API breaks.
- Keep the FFI surface small and explicit; do not expose Rust-internal abstractions or clever type machinery across UniFFI boundaries.
- Prefer owned values at FFI edges and async/callback boundaries; do not rely on borrowed data surviving across Swift callbacks or spawned tasks.

### Dependencies

- Use only crates listed in `docs/conventions.md`.
- Do not add `anyhow`, `cargo-insta`, or alternative HTTP/MCP crates without an architecture change.
- Prefer narrow dependencies and stable crate boundaries over convenience crates that increase API or runtime surface area.
- Do not introduce abstractions that assume `abridge_core` is a standalone backend service; embedded HTTP remains host-app controlled.

### Testing

- `#[cfg(test)]` modules and `tests/` integration tests only — no snapshot testing (`insta`).
- Primary test seam for bridge-backed calls: **`MockProviderBridge`** implementing `ProviderBridge`. Rust-native providers for Apple apps without a public framework bypass it; Notes uses SQLite fixture stores and attachment files in temporary directories (`notes/fixture.rs`, `notes/attachment_fixture.rs`). Never use the real Notes store or `osascript`; only the macOS-only rendition test may run `sips` on a fixture image.
- Cover `agent_shape` summary/detail consistency, omission, meaningful false outcomes, request rewrites, and binary content separation with framework JSON fixtures and the bridge seam. Cover shared `fuzzy` ranking/query semantics and Notes Markdown, filtering, and cache invalidation with fixture data.
- Test names: short and descriptive (`rejects_empty_token`) — not long Apollo-style sentences.
- Prefer seam-level tests for routing, auth, lifecycle, and callback behavior over end-to-end runtime coupling.
- Add focused tests for boundary behavior: error translation, callback ordering, graceful shutdown, and task cancellation where applicable.
- Run `TZ=UTC just test-rust` and `just lint-rust` before claiming done.
- Release builds (`just build-rust` / `build-macos.sh`) must **not** pass `--features test-sync`.

### Agent-facing responses and search

- `agent_shape/` owns client-facing shapes for bridge-backed providers and diagnostics; Swift keeps serializing framework objects. `mcp/mod.rs` applies shaping before delivery. Its `prepare` step may rewrite requests before dispatch, including listing contacts for fuzzy ranking.
- Notes shapes live in `notes/shape.rs`, Markdown rendering in `notes/markdown.rs`. Keep `notes/project.rs` internal to write confirmation.
- Reuse `crate::fuzzy` (`fuzzy.rs`, `nucleo-matcher`) for local text search, including Notes and contacts/events/reminders queries. Terms match inside a word, case-insensitive and accent-insensitive. A double-quoted segment is one exact phrase; a leading `'` does not quote spaces. Keep Apple's date/calendar/completion predicates; MapKit, Core Location, and Vision do not use fuzzy queries.
- Follow root `AGENTS.md` § Agent-shaped responses and `docs/conventions.md` for summary/detail shapes, omission, match evidence, binary content, and renditions.

### Rust-native app providers

- Only providers for Apple apps without a public framework (currently Notes) may bypass `ProviderBridge`. Framework-backed providers keep their Swift adapters.
- Notes may perform blocking read-only SQLite and attachment-file I/O in Rust. Use `SQLITE_OPEN_READ_ONLY` and one read transaction per snapshot; never mutate the real store.
- Notes may spawn `/usr/bin/osascript` for fixed JXA writes and `/usr/bin/sips` for image renditions, each with a timeout. Pass user input only as JSON on the script's stdin (`osascript -e` holds the fixed script; the payload is not an argument). Keep blocking provider work off Tokio's async workers.
- Rust owns serialized writes, outcome polling, and the Notes write-safety guards in root `AGENTS.md`. Agent-facing shapes, renditions, size limits, and approved crates follow `docs/conventions.md`.

### Patterns (optional, not required)

- **Type state** — optional for `ServerHandle`; the architecture guide's explicit lifecycle state machine is sufficient.
- **`#![deny(missing_docs)]`** — do not enable workspace-wide; document public UniFFI surface only when helpful.

### Public API design

- Favor explicit, stable public APIs over internal cleverness.
- FFI-visible structs, enums, and method signatures should model durable concepts, not incidental implementation details.
- Adding or changing FFI-visible fields, enum variants, error variants, or callback methods is an API review point, not a casual refactor.

### Panic and callback safety

- Any panic on a UniFFI-reachable path or callback-reachable path is a correctness bug; panics can abort the host app.
- Convert recoverable boundary failures into typed `CoreError` variants instead of crashing.
- Never hold locks while invoking Swift callbacks.
- Be conservative with spawned tasks, shared handles, and trait objects: reason explicitly about `Send + Sync`, ownership transfer, and shutdown behavior.

### Logging

- `tracing` only — no `log` crate. Disable ANSI in FFI contexts.

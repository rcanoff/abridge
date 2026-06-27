# AGENTS.md — rust/

Scoped rules for `apple_bridge_core`. Root `AGENTS.md` still applies.

## Required skills

All Rust work in this directory requires **rust-best-practices** before writing or reviewing code.

## Overrides (mandatory)

These supersede **rust-best-practices** and generic Rust advice. `docs/conventions.md` is canonical when this file and the skill disagree.

### Errors

- Use **`thiserror` only** — do not add `anyhow` (this crate is a `staticlib` exposed via UniFFI, not a standalone binary).
- Expose errors as **`CoreError`** with `#[derive(uniffi::Error)]`.
- Return `Result<T, CoreError>` on all user-input and external-data paths.
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
- Do not introduce abstractions that assume `apple_bridge_core` is a standalone backend service; embedded HTTP remains host-app controlled.

### Testing

- `#[cfg(test)]` modules and `tests/` integration tests only — no snapshot testing (`insta`).
- Primary test seam: **`MockProviderBridge`** implementing `ProviderBridge`.
- Test names: short and descriptive (`rejects_empty_token`) — not long Apollo-style sentences.
- Prefer seam-level tests for routing, auth, lifecycle, and callback behavior over end-to-end runtime coupling.
- Add focused tests for boundary behavior: error translation, callback ordering, graceful shutdown, and task cancellation where applicable.
- Run `TZ=UTC just test-rust` and `just lint-rust` before claiming done.

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

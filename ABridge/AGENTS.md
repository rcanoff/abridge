# AGENTS.md — ABridge (Swift target)

Scoped rules for the macOS app target. Root `AGENTS.md` still applies.

## Providers (`Providers/`)

- Swift providers stay thin: call Apple frameworks and serialize their objects for the Rust boundary.
- Rust `agent_shape` owns the agent-facing summary/detail shapes, omission, search ranking, and binary content separation.
- Follow root `AGENTS.md` § Agent-shaped responses and `docs/conventions.md` § JSON and payloads.

## Required skills

Read **swiftui-pro** before writing or reviewing SwiftUI in this directory.

- **Views, stores, app structure** → swiftui-pro
- **Concurrency changes** → when **swift-concurrency-pro** is installed, read it too
- Follow `docs/conventions.md` for naming, errors, and formatting
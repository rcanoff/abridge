# Apple Bridge

Native macOS app exposing Apple platform capabilities through a local, authenticated MCP server. A generic bridge between Apple frameworks and external clients—AI agents, desktop apps, scripts, and automation tools—without embedding application-specific logic.

**Status:** Menu bar shell, Rust MCP/HTTP server (health + bearer auth), Swift ↔ Rust via UniFFI. V1 provider: EventKit (Reminders + Calendar).

## CI status

[![Rust CI](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-rust.yml/badge.svg)](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-rust.yml)
[![macOS CI](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-macos.yml/badge.svg)](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-macos.yml)

Rust CI runs on Linux when `rust/` changes (fmt, clippy, tests). macOS CI runs when Swift, Xcode project, or Rust bindings change (SwiftFormat, SwiftLint, UniFFI build, tests).

## What it does

- Exposes Apple-native APIs through MCP on `127.0.0.1` (default port `3020`)
- Keeps Apple frameworks as the system of record (no user data store)
- Uses a thin SwiftUI shell for configuration and monitoring
- Centralizes server behavior, routing, and auth in Rust via UniFFI

## Architecture

- **Swift** — UI, permissions, Keychain, and thin provider adapters
- **Rust** — MCP/HTTP server, auth, routing, provider registry, and tests

See [architecture guide](docs/architecture-bootstrap-guide.md) for bootstrap steps and endpoint design.

## Project map

| Path | Purpose |
|------|---------|
| `AppleBridge/` | SwiftUI app, stores, services, thin providers |
| `AppleBridgeTests/` | Swift Testing unit tests |
| `rust/apple_bridge_core/` | MCP/HTTP server, auth, routing, Rust tests |
| `AppleBridgeCore/` | Generated XCFramework (do not edit) |
| `project.yml` | XcodeGen source — run `xcodegen generate` after edits |
| `justfile` | Task runner for dev and CI |
| `.githooks/` | Git hooks (verify + optional review chain) |
| `local/review/` | Local agent PR review (gitignored) |
| `docs/` | PRD, conventions, architecture guide |

## Prerequisites

macOS 26+, Xcode 26+, Rust 1.85+, [just](https://github.com/casey/just), [xcodegen](https://github.com/yonaskolb/XcodeGen), SwiftFormat, SwiftLint (`brew install swiftformat swiftlint`).

## Quick start

```sh
git clone git@github.com:rcanoff/apple-bridge.git
cd apple-bridge
xcodegen generate
just build-rust
open AppleBridge.xcodeproj
```

## Development commands

| Command | Purpose |
|---------|---------|
| `just test-swift` | Swift unit tests |
| `just test-rust` | Rust tests |
| `just lint-rust` | Rust fmt + clippy |
| `just fmt-check-swift` | SwiftFormat lint |
| `just lint-swift` | SwiftLint |
| `just ci` | Full local CI parity (macOS) |
| `just ci-rust` | Rust CI subset |
| `just ci-macos` | macOS CI subset |
| `just review` | Local agent code review |

## CI

Hybrid pipelines in `.github/workflows/`:

| Workflow | Runner | Triggers when |
|----------|--------|---------------|
| `ci-rust.yml` | Linux | `rust/**` changes |
| `ci-macos.yml` | macOS | `AppleBridge/**`, `AppleBridgeTests/**`, `project.yml`, `rust/**` |

Not automated in CI: EventKit permission dialogs, interactive Keychain, E2E MCP sessions. See `docs/conventions.md`.

## Contributing

- Branch naming: `feat/…`, `chore/…` (see `AGENTS.md`)
- Before opening a PR: `just preflight` (alias for `just ci` — run locally to save macOS CI minutes)
- Install hooks: `git config core.hooksPath .githooks`
- Agent rules: `AGENTS.md`
- Deep reference: `docs/conventions.md`, `docs/architecture-bootstrap-guide.md`, `docs/prd.md`
# Apple Bridge

Apple Bridge is a native macOS application that exposes Apple platform capabilities through a local, authenticated MCP server. It acts as a generic bridge between Apple frameworks and external clients—AI agents, desktop apps, scripts, and automation tools—without embedding application-specific logic.

## What it does

- Exposes Apple-native APIs through MCP on `localhost`
- Keeps Apple frameworks as the system of record (no user data store)
- Uses a thin SwiftUI shell for configuration and monitoring
- Centralizes server behavior, routing, and auth in Rust via UniFFI

## Version 1

The first release implements a single provider: **EventKit**, covering Reminders and Calendar with minimal abstraction over Apple's APIs.

## Architecture

- **Swift** — UI, permissions, Keychain, and thin provider adapters
- **Rust** — MCP/HTTP server, auth, routing, provider registry, and tests

## Status

Early bootstrap. Application code is not yet present in this repository.
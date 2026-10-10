# ABridge — Product Requirements Document

## Overview

ABridge is a native macOS application that exposes Apple platform capabilities through a local, authenticated MCP server.

Its purpose is to act as a generic bridge between Apple frameworks and external applications.

ABridge contains no application-specific logic. It does not know who is consuming it, why requests are made, or what higher-level workflows exist. It simply exposes native Apple functionality in a secure, modular, and predictable way.

The application is intended to become a reusable platform for Apple framework integrations.

---

# Goals

- Expose Apple-native APIs through MCP.
- Provide a single local endpoint for all Apple integrations.
- Keep Apple framework integration isolated from application logic.
- Make new Apple framework integrations straightforward to add.
- Keep the bridge generic and reusable.
- Minimize Swift code.
- Centralize all non-platform logic in Rust.

---

# Non-goals

ABridge is not:

- a productivity application
- a reminders application
- a calendar application
- a workflow engine
- an automation platform
- an AI agent
- an orchestration engine
- a synchronization service
- a cloud service
- a separate background daemon or launchd service (the MCP server runs inside the menu bar app process)

Business logic belongs to the MCP client, not to ABridge.

---

# Design Principles

The project follows several core principles.

## Generic

ABridge should never make assumptions about the software consuming it.

It should be equally usable by:

- AI agents
- desktop applications
- automation platforms
- scripts
- future integrations

## Thin wrapper

Whenever practical, ABridge should expose Apple APIs with minimal abstraction.

The bridge should not invent alternative domain models unless required by the MCP protocol.

## Apple is the source of truth

ABridge owns no user data.

Apple frameworks remain the system of record.

The application stores only:

- configuration
- authentication credentials
- operational state
- local usage audit logs (operational metadata only — not Apple framework data)

## Modular

Every Apple framework is implemented as an independent provider.

Adding a provider should not require modifying existing providers.

---

# Architecture

The architecture is defined in:

`docs/architecture-bootstrap-guide.md`

That document is the authoritative architectural specification for this project.

It defines:

- repository layout
- Swift/Rust boundaries
- provider architecture
- server lifecycle
- UniFFI integration
- authentication
- testing
- build system

Coding conventions (naming, libraries, formatting, error handling) are defined in:

`docs/conventions.md`

This document intentionally does not duplicate architectural or coding-convention details.

---

# Version 1 Scope

Version 1 implements a single provider:

**EventKit**

The objective is to expose the complete EventKit framework through MCP with minimal abstraction.

Version 1 includes complete support for the EventKit APIs available on macOS.

This includes both EventKit domains:

- Reminders
- Calendar

The bridge should expose Apple functionality rather than implementing custom reminder or calendar behavior.

---

# EventKit Provider

The EventKit provider should expose the capabilities supported by Apple's EventKit framework.

The provider should expose the framework as faithfully as practical instead of creating a custom abstraction layer.

## Reminders

Including, but not limited to:

- reminder lists
- reminders
- create
- update
- delete
- complete
- uncomplete
- notes
- due dates
- start dates
- alarms
- recurrence
- priorities
- search
- filtering
- calendar assignment
- move operations

## Calendar

Including, but not limited to:

- calendars
- events
- recurring events
- attendees (where supported)
- locations
- availability
- notes
- URLs
- alarms
- search
- create
- update
- delete

Whenever Apple expands EventKit, the provider should evolve to expose those capabilities while preserving the same architectural principles.

---

# Future Providers

The architecture is intentionally provider-based.

Future providers include:

- MapKit / CoreLocation
- Contacts
- HealthKit
- PhotoKit
- Vision

Additional Apple frameworks may be added over time.

Each provider should be self-contained and follow the architecture defined in `architecture-bootstrap-guide.md`.

---

# Runtime Model

ABridge is a **menu bar agent** — a single macOS application process that embeds the MCP HTTP server in Rust. There is no separate background service or daemon.

The user has full control over availability:

- **Launch at login** is optional and off by default. When enabled, the app starts at user login via `SMAppService.mainApp`.
- **MCP server state** is independent of launch at login. The server restores whatever the user last chose: if MCP was enabled when the app last ran, it starts enabled on the next launch; if disabled, it stays off.
- Port, enabled capabilities, and other settings persist across launches.

Launch at login only brings the application process up. It does not force the MCP server on unless the user previously left it enabled.

---

# User Interface

The SwiftUI application exists only to configure and monitor the bridge.

Its responsibilities include:

- provider status
- permission status
- API key management (masked display, copy, reset)
- localhost port configuration
- launch at login toggle
- MCP server enable/disable
- server status
- diagnostics and usage logs

### Settings tabs

| Tab | Purpose |
|-----|---------|
| **MCP** | Server on/off, host, port, endpoint, API key |
| **Permissions** | EventKit capability tree with Apple vs MCP enforcement |
| **Diagnostics** | Usage log viewer, logging toggle, export |

The application is not intended to browse, edit, or manage Apple data directly.

---

# Networking

ABridge exposes a local authenticated MCP endpoint.

Characteristics:

- localhost only (`127.0.0.1`)
- configurable port (default `3020`)
- bearer token authentication
- no remote access by default

Networking behavior is defined by the architecture guide.

---

# Authentication

Version 1 uses a single **API key** transmitted as a Bearer token:

```
Authorization: Bearer <key>
```

### API key (V1)

| Aspect | Requirement |
|--------|-------------|
| Generation | Cryptographically random (256-bit entropy) |
| Format | Prefixed identifier, e.g. `ab_live_<random>` |
| Storage | macOS Keychain (Swift); Rust receives at runtime only |
| UI | Masked by default (e.g. `ab_live_••••••••3f9a`); Copy reveals full key |
| Rotation | User-initiated reset; server restarts with new key |
| Logging | Bearer tokens and API keys must never appear in logs |

`/health` does not require authentication. All MCP routes require a valid Bearer token.

### Future authentication

Version 1 ships Bearer-only. Future versions may add:

- multiple named, independently revocable API keys
- mutual TLS
- Unix domain socket transport with peer credentials
- request signing (HMAC)

These are not in Version 1 scope. The PRD will be updated when a specific alternative is chosen.

---

# Diagnostics and Usage Logging

ABridge records **local, operational usage metadata** to help users and MCP clients understand bridge activity. This is not Apple framework data and does not include request or response payloads.

### Recorded events (when logging is enabled)

| Field | Recorded |
|-------|----------|
| Timestamp (UTC) | Yes |
| MCP tool name | Yes |
| Success or failure | Yes |
| Duration (ms) | Yes |
| Request/response payloads | No |
| Bearer tokens | Never |

Lifecycle events are also captured: server start/stop, port bind, MCP client `initialize`, and API key rotation (event only — not the key value).

### User control

- **Record tool usage** toggle in Diagnostics (default: on).
- When off, new events are not recorded. Existing buffer remains readable until cleared or rotated out.
- Logs are local only — no cloud sync or remote telemetry.

### Storage

- In-memory ring buffer (bounded, e.g. last 1,000 events).
- Optional persistence to a local log file under `~/Library/Logs/ABridge/`.
- Rust owns collection and retention; Swift surfaces logs in the Diagnostics UI.

### MCP diagnostics tool

A read-only MCP tool (`diagnostics_get_usage_log`) returns the accumulated audit log as JSON. It requires normal Bearer authentication. When logging is disabled, the tool still responds but indicates that recording is off and returns only previously captured entries (if any).

---

# Data Ownership

ABridge stores only:

- application configuration
- authentication credentials
- operational state
- local usage audit logs (metadata only)

All user data remains owned by Apple frameworks.

The project should not introduce an application database unless a future provider explicitly requires one.

---

# Success Criteria

ABridge is successful when:

- it exposes Apple frameworks through a stable local MCP endpoint
- Swift remains limited to UI and Apple platform integration
- Rust owns all application behavior
- providers remain completely independent
- Apple frameworks remain the system of record
- new providers can be added without architectural changes
- the bridge remains completely unaware of the software consuming it
- Apple APIs are exposed with minimal abstraction
- users control launch-at-login and MCP server state independently
- usage can be inspected locally and via a read-only MCP diagnostics tool
- API keys are strong, masked in the UI, and never logged
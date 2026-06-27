# Apple Bridge — Product Requirements Document

## Overview

Apple Bridge is a native macOS application that exposes Apple platform capabilities through a local, authenticated MCP server.

Its purpose is to act as a generic bridge between Apple frameworks and external applications.

Apple Bridge contains no application-specific logic. It does not know who is consuming it, why requests are made, or what higher-level workflows exist. It simply exposes native Apple functionality in a secure, modular, and predictable way.

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

Apple Bridge is not:

- a productivity application
- a reminders application
- a calendar application
- a workflow engine
- an automation platform
- an AI agent
- an orchestration engine
- a synchronization service
- a cloud service

Business logic belongs to the MCP client, not to Apple Bridge.

---

# Design Principles

The project follows several core principles.

## Generic

Apple Bridge should never make assumptions about the software consuming it.

It should be equally usable by:

- AI agents
- desktop applications
- automation platforms
- scripts
- future integrations

## Thin wrapper

Whenever practical, Apple Bridge should expose Apple APIs with minimal abstraction.

The bridge should not invent alternative domain models unless required by the MCP protocol.

## Apple is the source of truth

Apple Bridge owns no user data.

Apple frameworks remain the system of record.

The application stores only:

- configuration
- authentication credentials
- operational state

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

Additional Apple frameworks may be added over time.

Each provider should be self-contained and follow the architecture defined in `architecture-bootstrap-guide.md`.

---

# User Interface

Apple Bridge is primarily a background service.

The SwiftUI application exists only to configure and monitor the bridge.

Its responsibilities include:

- provider status
- permission status
- bearer token management
- localhost port configuration
- launch at login
- server status
- diagnostics
- logs

The application is not intended to browse, edit, or manage Apple data directly.

---

# Networking

Apple Bridge exposes a local authenticated MCP endpoint.

Characteristics:

- localhost only
- configurable port
- bearer token authentication
- no remote access by default

Networking behavior is defined by the architecture guide.

---

# Data Ownership

Apple Bridge stores only:

- application configuration
- authentication credentials
- operational state

All user data remains owned by Apple frameworks.

The project should not introduce an application database unless a future provider explicitly requires one.

---

# Success Criteria

Apple Bridge is successful when:

- it exposes Apple frameworks through a stable local MCP endpoint
- Swift remains limited to UI and Apple platform integration
- Rust owns all application behavior
- providers remain completely independent
- Apple frameworks remain the system of record
- new providers can be added without architectural changes
- the bridge remains completely unaware of the software consuming it
- Apple APIs are exposed with minimal abstraction
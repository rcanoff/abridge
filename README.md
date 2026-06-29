# Apple Bridge

**Apple frameworks on your Mac, one local MCP endpoint.**

Local MCP for native Apple apps on your Mac—Reminders, Calendars, Contacts, MapKit, and more. One endpoint that exposes Apple framework capabilities to any MCP client.

Apple Bridge is a **native macOS** menu bar app with a **Rust** MCP/HTTP core. Swift handles the UI, system permission prompts, and thin Apple framework adapters; Rust owns the server, auth, routing, and tool registry (linked via UniFFI). It exposes platform capabilities through a local, authenticated MCP server on `127.0.0.1`—a generic bridge with no application-specific logic baked in.

**Transparent.** MCP payloads are faithful projections of Apple framework objects—mechanical JSON serialization, not reshaped domain models or hidden fields.

**Permissioned.** You grant access in two layers: macOS Apple permissions (e.g. Reminders), then per-capability MCP toggles in the app (Read, Create, Edit, Delete, and more). Only enabled capabilities appear in `tools/list`; everything else stays unavailable to your client.

### Connect your MCP client

| | |
|---|---|
| **Endpoint** | `http://127.0.0.1:3020/mcp` (default; configurable in the app) |
| **Auth** | Bearer token (copy from the menu bar app) |
| **Prerequisite** | Apple Bridge must be running before your client connects |

**Local only.** Binds to loopback, never ships your data to a cloud service. Apple frameworks remain the system of record.

**Status:** V1 provider EventKit — Reminders shipped; Calendars & Events planned.

## MCP capabilities

MCP tool names use dot notation (e.g. `eventkit.reminders.list_reminders`). Discover the live set via `tools/list`; call with `tools/call`.

### EventKit — Reminders (shipped)

**Lists**

- [x] `eventkit.reminders.list_lists`
- [x] `eventkit.reminders.create_list`
- [x] `eventkit.reminders.delete_list`

**Reminders**

- [x] `eventkit.reminders.list_reminders`
- [x] `eventkit.reminders.search_reminders`
- [x] `eventkit.reminders.get_reminder`
- [x] `eventkit.reminders.create_reminder`
- [x] `eventkit.reminders.update_reminder`
- [x] `eventkit.reminders.delete_reminder`
- [x] `eventkit.reminders.move_reminder`
- [x] `eventkit.reminders.complete_reminder`
- [x] `eventkit.reminders.uncomplete_reminder`
- [x] `eventkit.reminders.set_reminder_alarms`
- [x] `eventkit.reminders.set_reminder_recurrence`

<details>
<summary><strong>EventKit — Calendars & Events</strong> (planned)</summary>

**Calendars**

- [ ] `eventkit.calendars.list_calendars`
- [ ] `eventkit.calendars.create_calendar`
- [ ] `eventkit.calendars.update_calendar`
- [ ] `eventkit.calendars.delete_calendar`

**Events**

- [ ] `eventkit.events.list_events`
- [ ] `eventkit.events.search_events`
- [x] `eventkit.events.get_event`
- [x] `eventkit.events.create_event`
- [x] `eventkit.events.update_event`
- [x] `eventkit.events.delete_event`
- [x] `eventkit.events.move_event`
- [x] `eventkit.events.set_event_alarms`
- [x] `eventkit.events.set_event_recurrence`
- [ ] `eventkit.events.accept_invitation`
- [ ] `eventkit.events.decline_invitation`
- [ ] `eventkit.events.tentative_invitation`

</details>

<details>
<summary><strong>Contacts</strong> (planned)</summary>

- [x] `contacts.list_contacts`
- [x] `contacts.search_contacts`
- [x] `contacts.get_contact`
- [x] `contacts.create_contact`
- [ ] `contacts.update_contact`
- [ ] `contacts.delete_contact`
- [ ] `contacts.link_contacts`
- [ ] `contacts.unlink_contacts`
- [ ] `contacts.list_groups`
- [ ] `contacts.create_group`
- [ ] `contacts.update_group`
- [ ] `contacts.delete_group`

</details>

<details>
<summary><strong>MapKit</strong> (planned)</summary>

- [ ] `mapkit.search_places`
- [ ] `mapkit.search_nearby`
- [ ] `mapkit.reverse_geocode`
- [ ] `mapkit.forward_geocode`
- [ ] `mapkit.calculate_route`
- [ ] `mapkit.estimate_travel_time`
- [ ] `mapkit.open_navigation`
- [ ] `mapkit.lookup_place`
- [ ] `mapkit.get_current_location`

</details>

<details>
<summary><strong>Vision</strong> (planned)</summary>

- [ ] `vision.recognize_text`
- [ ] `vision.scan_document`
- [ ] `vision.read_qr_code`
- [ ] `vision.detect_barcodes`
- [ ] `vision.detect_faces`

</details>

<details>
<summary><strong>Out of scope</strong> (not planned)</summary>

**LocalAuthentication**

- [ ] `authentication.request_biometric_authentication`
- [ ] `authentication.check_biometric_availability`

**AVFoundation**

- [ ] `camera.capture_photo`
- [ ] `camera.start_video_recording`
- [ ] `camera.stop_video_recording`
- [ ] `microphone.start_recording`
- [ ] `microphone.stop_recording`

**CoreBluetooth**

- [ ] `bluetooth.scan_devices`
- [ ] `bluetooth.connect_device`
- [ ] `bluetooth.disconnect_device`
- [ ] `bluetooth.read_characteristic`
- [ ] `bluetooth.write_characteristic`

**HealthKit**

- [ ] `healthkit.list_data_types`
- [ ] `healthkit.read_samples`
- [ ] `healthkit.write_sample`
- [ ] `healthkit.delete_sample`

**CoreLocation**

- [ ] `location.get_current_location`
- [ ] `location.reverse_geocode`
- [ ] `location.forward_geocode`
- [ ] `location.start_updates`
- [ ] `location.stop_updates`

**Photos**

- [ ] `photos.list_albums`
- [ ] `photos.search_photos`
- [ ] `photos.get_photo`
- [ ] `photos.get_metadata`
- [ ] `photos.save_image`
- [ ] `photos.delete_photo`
- [ ] `photos.create_album`
- [ ] `photos.add_to_album`

**UserNotifications**

- [ ] `notifications.schedule_notification`
- [ ] `notifications.list_pending`
- [ ] `notifications.get_pending_notification`
- [ ] `notifications.remove_pending`
- [ ] `notifications.remove_all_pending`
- [ ] `notifications.list_delivered`
- [ ] `notifications.remove_delivered`
- [ ] `notifications.remove_all_delivered`

**HomeKit**

- [ ] `homekit.list_homes`
- [ ] `homekit.list_rooms`
- [ ] `homekit.list_accessories`
- [ ] `homekit.get_accessory`
- [ ] `homekit.control_accessory`
- [ ] `homekit.list_scenes`
- [ ] `homekit.execute_scene`

**MusicKit**

- [ ] `musickit.search`
- [ ] `musickit.get_album`
- [ ] `musickit.get_artist`
- [ ] `musickit.get_playlist`
- [ ] `musickit.play`
- [ ] `musickit.pause`
- [ ] `musickit.skip`

**Shortcuts**

- [ ] `shortcuts.list_shortcuts`
- [ ] `shortcuts.get_shortcut`
- [ ] `shortcuts.run_shortcut`

</details>

## CI

GitHub Actions workflows are **temporarily disabled** (manual `workflow_dispatch` only). Run CI locally before pushing:

```sh
just preflight   # alias for `just ci` — Rust + macOS steps
```

| Command | What it runs |
|---------|----------------|
| `just ci` | Full local CI parity (`ci-rust` + `ci-macos-steps` on macOS) |
| `just ci-rust` | Rust fmt, clippy, tests (Linux or macOS) |
| `just ci-macos` | SwiftFormat, SwiftLint, UniFFI build, Swift tests (macOS only) |

Workflow definitions remain in `.github/workflows/` for when Actions are re-enabled.

Not automated in CI: EventKit permission dialogs, interactive Keychain, E2E MCP sessions. See `docs/conventions.md`.

## What it does

- Thin SwiftUI menu bar shell for configuration, permissions, and server monitoring
- Rust core owns MCP/HTTP transport, bearer auth, routing, and provider registry (Swift ↔ Rust via UniFFI)
- Pluggable providers: thin Swift adapters call Apple frameworks; MCP exposes faithful JSON projections

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

Build and run the app, start the server from the menu bar, then point your MCP client at the endpoint above.

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

## Contributing

- Branch naming: `feat/…`, `chore/…` (see `AGENTS.md`)
- Before opening a PR: `just preflight` (alias for `just ci`)
- Install hooks: `git config core.hooksPath .githooks`
- Agent rules: `AGENTS.md`
- Deep reference: `docs/conventions.md`, `docs/architecture-bootstrap-guide.md`, `docs/prd.md`
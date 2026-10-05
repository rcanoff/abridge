<br/>
<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="icon/mark-dark.png">
    <img src="icon/mark.png" width="200px" alt="Apple Bridge"></img>
  </picture>
</p>

# Apple Bridge

**Apple frameworks on your Mac, one local MCP endpoint.**

A native macOS menu bar app with a Rust MCP/HTTP core. Swift owns the UI, system permission prompts, and thin Apple adapters. Rust owns the server, auth, routing, and tool registry (UniFFI). Clients talk to `127.0.0.1` only.

Providers: EventKit (Reminders, Calendars, Events), Contacts, MapKit, and Vision. MCP payloads are mechanical JSON of Apple objects: no reshaped domain models, no hidden fields.

Access is two layers: macOS privacy permission, then per-capability MCP toggles in Settings. Only enabled capabilities appear in `tools/list`. Reminders lists and event calendars default to sharing all of them; Permissions can restrict MCP to a subset.

### Connect your MCP client

| | |
|---|---|
| **Endpoint** | `http://127.0.0.1:3020/mcp` (default; configurable in the app) |
| **Auth** | Bearer token (copy from the menu bar app) |
| **Prerequisite** | Apple Bridge must be running before your client connects |

Binds to loopback. Apple frameworks remain the system of record.

## Install

Requires macOS 26+ on Apple silicon.

```sh
brew install --cask rcanoff/tap/apple-bridge
```

Or download `AppleBridge-<version>.dmg` from [Releases](https://github.com/rcanoff/apple-bridge/releases) and drag Apple Bridge to Applications. Builds are Developer ID signed and notarized.

Apple Bridge updates itself through Sparkle: **Check for Updates…** in the menu bar, plus scheduled checks once you allow them.

## Build from source

```sh
git clone git@github.com:rcanoff/apple-bridge.git
cd apple-bridge
xcodegen generate
just build-rust
open AppleBridge.xcodeproj
```

Build and run the app, start the server from the menu bar, then point your MCP client at the endpoint above.

Builds are ad-hoc signed by default, so every rebuild has a new signature and macOS asks again for Keychain access to the API key and for privacy permissions. To sign local builds with your development certificate instead, create `Configs/Local.xcconfig` (gitignored) with your team:

```
DEVELOPMENT_TEAM = <your team ID>
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Apple Development
```

Choose **Always Allow** at the next Keychain prompt; later rebuilds keep that grant.

## Prerequisites

macOS 26+, Xcode 26+, Rust 1.85+, [just](https://github.com/casey/just), [xcodegen](https://github.com/yonaskolb/XcodeGen), SwiftFormat, SwiftLint (`brew install swiftformat swiftlint`).

Icon tracing (`just gen-icon-svg`) also needs ImageMagick and potrace.

## MCP tools

Tool names use `<provider>.<domain>.<operation>`. Discover the live set with `tools/list`; call with `tools/call`.

### EventKit: Reminders

- `eventkit.reminders.list_lists`
- `eventkit.reminders.create_list`
- `eventkit.reminders.delete_list`
- `eventkit.reminders.list_reminders`
- `eventkit.reminders.search_reminders`
- `eventkit.reminders.get_reminder`
- `eventkit.reminders.create_reminder`
- `eventkit.reminders.update_reminder`
- `eventkit.reminders.delete_reminder`
- `eventkit.reminders.move_reminder`
- `eventkit.reminders.complete_reminder`
- `eventkit.reminders.uncomplete_reminder`
- `eventkit.reminders.set_reminder_alarms`
- `eventkit.reminders.set_reminder_recurrence`

### EventKit: Calendars and Events

- `eventkit.calendars.list_calendars`
- `eventkit.calendars.create_calendar`
- `eventkit.calendars.update_calendar`
- `eventkit.calendars.delete_calendar`
- `eventkit.events.list_events`
- `eventkit.events.search_events`
- `eventkit.events.get_event`
- `eventkit.events.create_event`
- `eventkit.events.update_event`
- `eventkit.events.delete_event`
- `eventkit.events.move_event`
- `eventkit.events.set_event_alarms`
- `eventkit.events.set_event_recurrence`

Invitation RSVP (`accept_invitation`, `decline_invitation`, `tentative_invitation`) is not supported.

### Contacts

- `contacts.list_contacts`
- `contacts.search_contacts`
- `contacts.get_contact`
- `contacts.create_contact`
- `contacts.update_contact`
- `contacts.delete_contact`
- `contacts.link_contacts`
- `contacts.unlink_contacts`
- `contacts.list_groups`
- `contacts.create_group`
- `contacts.update_group`
- `contacts.delete_group`

### MapKit

- `mapkit.search_places`
- `mapkit.search_nearby`
- `mapkit.reverse_geocode`
- `mapkit.forward_geocode`
- `mapkit.calculate_route`
- `mapkit.estimate_travel_time`
- `mapkit.open_navigation`
- `mapkit.lookup_place`
- `mapkit.get_current_location`

### Vision

- `vision.recognize_text`
- `vision.scan_document`
- `vision.read_qr_code`
- `vision.detect_barcodes`
- `vision.detect_faces`

### Diagnostics

- `diagnostics.get_usage_log`

### Not supported

LocalAuthentication, AVFoundation, CoreBluetooth, HealthKit, PhotoKit, UserNotifications, HomeKit, MusicKit, Shortcuts.

## Architecture

- **Swift:** UI, permissions, Keychain, thin Apple adapters
- **Rust:** MCP/HTTP server, auth, routing, provider registry, tests

See the [architecture guide](docs/architecture-bootstrap-guide.md) for bootstrap steps and endpoint design.

Settings tabs: MCP, Permissions, Diagnostics, Developer.

## Project map

| Path | Purpose |
|------|---------|
| `AppleBridge/` | SwiftUI app, stores, services, thin providers, app icon, menu-bar mark |
| `AppleBridgeTests/` | Swift Testing unit tests |
| `rust/apple_bridge_core/` | MCP/HTTP server, auth, routing, Rust tests |
| `AppleBridgeCore/` | Generated by `just build-rust`. Not committed. Do not edit. |
| `icon/` | Mark source: preview, SVG, Icon Composer, README tiles |
| `project.yml` | XcodeGen source. Run `xcodegen generate` after edits |
| `justfile` | Task runner for dev and CI |
| `.githooks/` | Git hooks (verify and optional review chain) |
| `local/review/` | Local agent PR review (gitignored) |
| `docs/` | PRD, conventions, architecture guide |

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
| `just gen-icon-svg` | Trace `icon/previews/mark.jpg` to SVG |
| `just gen-menubar-icons` | Rasterize the SVG into the menu-bar template |
| `just release-build <version>` | Signed, notarized DMG and Sparkle appcast in `build/release/` |

## CI

CI workflows are `workflow_dispatch` only. Run CI locally before pushing:

```sh
just preflight   # alias for `just ci`: Rust + macOS steps
```

| Command | What it runs |
|---------|----------------|
| `just ci` | Full local CI parity (`ci-rust` + `ci-macos-steps` on macOS) |
| `just ci-rust` | Rust fmt, clippy, tests (Linux or macOS) |
| `just ci-macos` | SwiftFormat, SwiftLint, UniFFI build, Swift tests (macOS only) |

Workflow definitions stay in `.github/workflows/`.

Not automated in CI: EventKit permission dialogs, interactive Keychain, E2E MCP sessions. See `docs/conventions.md`.

## Releasing

Push a `vX.Y.Z` tag from `main`. The [Release workflow](.github/workflows/release.yml) builds the Rust core, archives a Developer ID signed build with the hardened runtime, notarizes and staples the app and DMG, generates the Sparkle `appcast.xml`, publishes both to a GitHub release, and updates the cask in [rcanoff/homebrew-tap](https://github.com/rcanoff/homebrew-tap). The job runs in the `release` environment (Settings → Environments): its secrets, listed in the workflow header, reach only `v*` tag runs approved by a required reviewer.

```sh
git tag v1.0.0 && git push origin v1.0.0
```

- `CFBundleShortVersionString` comes from the tag; `CFBundleVersion` is the commit count of the tagged commit, so Sparkle sees every release as newer.
- The app reads its feed from `releases/latest/download/appcast.xml`, so the repository must be public for updates and Homebrew downloads to work.
- The Sparkle EdDSA private key signs every update; keep a backup outside CI. Losing it strands installed copies on their current version.
- Local build: `just release-build 1.0.0` (environment variables are documented at the top of `scripts/release.sh`); add `--skip-notarization` to check signing and packaging without submitting to Apple.

## Contributing

- Branch naming: `feat/...`, `chore/...` (see `AGENTS.md`)
- Before opening a PR: `just preflight`
- Install hooks: `git config core.hooksPath .githooks`
- Agent rules: `AGENTS.md`
- Deep reference: `docs/conventions.md`, `docs/architecture-bootstrap-guide.md`, `docs/prd.md`

## License

This repository is licensed under the [Apache License 2.0](LICENSE.md).

## Security

Report vulnerabilities privately. See [SECURITY.md](SECURITY.md).

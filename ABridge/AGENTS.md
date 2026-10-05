# AGENTS.md — ABridge (Swift target)

Scoped rules for the macOS app target. Root `AGENTS.md` still applies.

## Providers (`Providers/`)

- **Framework fidelity is mandatory** — root `AGENTS.md` § Framework fidelity.
- `EventKitProvider` and mappers serialize **full** `EKReminder` / `EKCalendar` (and related) objects; no field subsetting or semantic renames in production paths.
- Reviews must reject partial read models (see `local/review/AGENTS.md` § Framework fidelity).

## Required skills

All Swift and SwiftUI work in this directory requires **swiftui-pro** before writing or reviewing code.

- **Views, stores, app structure** → swiftui-pro
- **Concurrency changes** → also swift-concurrency-pro
- Follow `docs/conventions.md` for naming, errors, and formatting
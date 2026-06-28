# CI Pipelines & README — Design Spec

**Date:** 2026-06-27  
**Status:** Approved  
**Scope:** GitHub Actions (hybrid Linux/macOS), `just` CI recipes, pre-push hook, README refresh

---

## Summary

Add path-filtered CI pipelines for PRs: Rust lint and tests on Linux, Swift hygiene + tests + Rust build on macOS when relevant paths change. Mirror CI locally via `just ci` and an optional path-aware pre-push hook. Refresh the README as a contributor onboarding front door with a project map.

Local agent review (`just review`) stays separate and gitignored — CI handles verification, review stays advisory.

---

## Decisions

| Topic | Choice |
|-------|--------|
| CI platform | Hybrid: Linux for Rust; macOS for Swift + UniFFI build |
| macOS trigger | Path-filtered (not every PR) |
| Swift hygiene | SwiftFormat + SwiftLint in v1 |
| README shape | Contributor guide + project map |
| Local parity | `just ci` + optional pre-push hook (fast subset) |
| Workflow layout | Two files: `ci-rust.yml` + `ci-macos.yml` |
| README CI badges | Two workflow badges (Rust CI + macOS CI) |

---

## CI architecture

### `ci-rust.yml` (Linux)

- **Workflow name:** `Rust CI` (shown on badge label)
- **Triggers:** pull requests and pushes to `main`, when `rust/**` changes
- **Runner:** `ubuntu-latest`
- **Command:** `just ci-rust` (= `lint-rust` + `test-rust`)
- **Toolchain:** Rust from `rust-toolchain.toml` if present, otherwise stable; install `just`

### `ci-macos.yml` (path-filtered)

- **Workflow name:** `macOS CI` (shown on badge label)
- **Triggers:** pull requests and pushes to `main`, when any of these change:
  - `AppleBridge/**`
  - `AppleBridgeTests/**`
  - `project.yml`
  - `rust/**`
- **Runner:** latest available GitHub-hosted macOS runner
- **Command:** `just ci-macos`
- **Prerequisites:** install Rust, `just`, SwiftFormat, SwiftLint (e.g. via Homebrew)

### Path-filter behavior

| PR touches | Linux | macOS |
|------------|-------|-------|
| `rust/**` only | ✓ | ✓ (bindings/build) |
| Swift paths only | — | ✓ |
| Both | ✓ | ✓ |
| Docs / tooling only | — | — |

### Out of CI

Per `docs/conventions.md`:

- EventKit permission dialogs
- Interactive Keychain access
- End-to-end MCP client sessions
- Local agent review (`just review`)

---

## `just` recipes & Swift tooling

### New recipes

| Recipe | Runs |
|--------|------|
| `fmt-check-swift` | SwiftFormat lint mode on `AppleBridge/`, `AppleBridgeTests/` |
| `lint-swift` | SwiftLint (strict — violations fail) |
| `ci-rust` | `lint-rust` + `test-rust` |
| `ci-macos` | `fmt-check-swift` + `lint-swift` + `test-swift` + `build-rust` |
| `ci` | `ci-rust` + `ci-macos` (macOS steps skip with a clear message on non-macOS hosts) |

Existing recipes (`test-swift`, `test-rust`, `lint-rust`, etc.) stay for day-to-day use. CI and pre-push call the `ci-*` wrappers.

### SwiftFormat

- Config at repo root (`.swiftformat`)
- Scope: `AppleBridge/`, `AppleBridgeTests/`
- Exclude generated paths: `apple_bridge_core.swift`, `AppleBridgeCore/`

### SwiftLint

- Config at repo root (`.swiftlint.yml`)
- Same scope and excludes as SwiftFormat
- Default ruleset with minimal project-specific opt-outs for v1

### Version pinning (v1)

Document minimum tool versions in README; link to `docs/conventions.md` for deep reference. Reproducible install tooling (Brewfile, `mise`, etc.) is a follow-up, not required for v1.

---

## Pre-push hook

### Location

Tracked under `.githooks/` (review tooling under `local/` stays gitignored). Install via:

```sh
git config core.hooksPath .githooks
```

### Behavior

1. **Path detection** — compare push refs against `origin/main` (configurable base) using the same path globs as CI workflows
2. **Fast verify:**
   - `rust/**` changed → `just ci-rust`
   - Swift paths changed → `fmt-check-swift` + `lint-swift` + `test-swift`
   - Both → Rust first, then Swift
   - Neither → skip with message
3. **Skipped on pre-push** (CI still runs these):
   - `build-rust` — too slow for every push
4. **Review chaining** — after verify, delegate to `local/review/bin/review.sh --hook` if installed (existing advisory/strict behavior via `REVIEW_STRICT=1`)

### Strict mode

| Variable | Effect |
|----------|--------|
| `CI_STRICT=1` | verify failures block push |
| `REVIEW_STRICT=1` | review failures block push (existing) |
| default | advisory — warn, push proceeds |

Path-matching logic lives in a small shared script (`scripts/ci/paths.sh`) used by the pre-push hook so local and CI rules stay aligned.

---

## README outline

The README is the onboarding front door. Deep reference stays in `docs/conventions.md` and `docs/architecture-bootstrap-guide.md`.

### Sections

1. **Header** — description, accurate project status (replace stale "no application code" note)
2. **CI status** — two workflow badges (see below)
3. **What it does** — MCP on localhost, Apple as source of truth, V1 EventKit scope
4. **Architecture (brief)** — Swift shell + Rust core; link to architecture guide
5. **Project map** — table of `AppleBridge/`, `AppleBridgeTests/`, `rust/`, `AppleBridgeCore/`, `project.yml`, `justfile`, `.githooks/`, `local/review/`, `docs/`
6. **Prerequisites** — macOS 26+, Xcode 26+, Rust, `just`, `xcodegen`, SwiftFormat, SwiftLint
7. **Quick start** — clone, `xcodegen generate`, `just build-rust`, open Xcode
8. **Development commands** — `just` recipe table (`test-*`, `lint-*`, `ci`, `review`)
9. **CI overview** — hybrid model, path filters, what's not automated
10. **Contributing pointers** — branch naming, `just ci` before PR, hook install, `AGENTS.md`

### CI status badges

Two GitHub Actions workflow badges — one per pipeline. Each badge reflects the last run on the default branch (`main`); clicking opens the workflow in Actions. Badges appear after workflows exist and have run at least once.

```markdown
## CI status

[![Rust CI](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-rust.yml/badge.svg)](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-rust.yml)
[![macOS CI](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-macos.yml/badge.svg)](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-macos.yml)

Rust CI runs on Linux when `rust/` changes (fmt, clippy, tests). macOS CI runs when Swift, Xcode project, or Rust bindings change (SwiftFormat, SwiftLint, tests, UniFFI build).
```

Do not split into separate lint/test/build badges — one badge per workflow is enough for v1. Path-filtered workflows may not run on docs-only merges; the badge then shows the previous run result (expected behavior).

### Principle

README orients a new contributor in minutes. Do not duplicate formatting rules, library pins, or architecture depth — link instead.

---

## Rejected alternatives

| Alternative | Reason |
|-------------|--------|
| macOS-only CI | Wastes Linux runners; Rust checks are platform-independent |
| macOS on every PR | Slow and costly when changes are Rust-only or docs-only |
| Single monolithic workflow | Harder to read than split `ci-rust` / `ci-macos` files |
| Callable reusable workflows | Over-engineered for v1 |
| Swift tests only (no format/lint) | User wants full Swift hygiene in v1 |
| `just ci` without pre-push | User wants local parity plus fast push-time feedback |
| Per-step lint/test badges | Extra workflows for little benefit; two workflow badges suffice |
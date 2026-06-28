# CI Pipelines & README — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add hybrid GitHub Actions CI (Rust on Linux, Swift+build on path-filtered macOS), local `just ci` parity, path-aware pre-push hook, and a contributor-focused README with CI badges.

**Architecture:** Two workflow files call `just ci-rust` / `just ci-macos`. Swift hygiene via SwiftFormat + SwiftLint configs at repo root. Pre-push uses shared `scripts/ci/paths.sh` for the same path globs as CI. README becomes onboarding front door; deep reference stays in `docs/conventions.md`.

**Tech Stack:** GitHub Actions (`ubuntu-latest`, `macos-15`), `just`, SwiftFormat, SwiftLint, Rust 1.85, xcodebuild

**Spec:** `docs/superpowers/specs/2026-06-27-ci-pipelines-readme-design.md`  
**Branch:** `chore/ci-pipelines-readme`

---

## File Map

| File | Responsibility |
|------|----------------|
| `.github/workflows/ci-rust.yml` | Linux Rust CI on `rust/**` changes |
| `.github/workflows/ci-macos.yml` | macOS CI on Swift/project/rust binding changes |
| `.swiftformat` | Swift format rules + excludes for generated code |
| `.swiftlint.yml` | Swift lint rules + excludes |
| `justfile` | `fmt-check-swift`, `lint-swift`, `ci-rust`, `ci-macos`, `ci` |
| `scripts/ci/paths.sh` | Shared path-change detection (rust vs swift globs) |
| `scripts/ci/pre-push-verify.sh` | Fast pre-push verify (no `build-rust`) |
| `.githooks/pre-push` | Verify hook + optional review chain |
| `.githooks/README.md` | Hook install instructions |
| `README.md` | Contributor onboarding + CI badges + project map |
| `docs/conventions.md` | SwiftFormat/SwiftLint + CI section |
| `AGENTS.md` | Verification matrix + `just ci` references |

---

## Prerequisites

- [ ] On `main`, up to date
- [ ] `just test-all` green locally
- [ ] `brew install swiftformat swiftlint` available on dev machine (for Task 2–3)

---

### Task 1: `just ci-rust` + Rust CI workflow

**Files:**
- Modify: `justfile`
- Create: `.github/workflows/ci-rust.yml`

- [ ] **Step 1: Create branch**

```bash
git checkout main
git pull origin main
git checkout -b chore/ci-pipelines-readme
```

- [ ] **Step 2: Add `ci-rust` to `justfile`**

Append after `lint-rust` recipe:

```just
ci-rust: _rust-workspace
    just lint-rust
    just test-rust
```

- [ ] **Step 3: Verify locally**

Run: `just ci-rust`  
Expected: fmt-check passes, clippy passes, all Rust tests pass

- [ ] **Step 4: Create `.github/workflows/ci-rust.yml`**

```yaml
name: Rust CI

on:
  push:
    branches: [main]
    paths:
      - "rust/**"
  pull_request:
    paths:
      - "rust/**"

concurrency:
  group: rust-ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  rust:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@master
        with:
          toolchain: "1.85"
          components: rustfmt, clippy

      - uses: extractions/setup-just@v2

      - name: Rust CI
        run: just ci-rust
        env:
          TZ: UTC
```

- [ ] **Step 5: Commit**

```bash
git add justfile .github/workflows/ci-rust.yml
git commit -m "chore: add Rust CI workflow and just ci-rust recipe"
```

---

### Task 2: SwiftFormat config + `fmt-check-swift`

**Files:**
- Create: `.swiftformat`
- Modify: `justfile`
- Modify: Swift sources under `AppleBridge/`, `AppleBridgeTests/` (format fixes only)

- [ ] **Step 1: Create `.swiftformat`**

```
--swiftversion 6.0
--indent 4
--maxwidth 120
--exclude AppleBridge/Services/apple_bridge_core.swift
--exclude AppleBridgeCore
```

- [ ] **Step 2: Add recipes to `justfile`**

```just
_swift-sources := "AppleBridge AppleBridgeTests"
_swift-exclude := "--exclude AppleBridge/Services/apple_bridge_core.swift --exclude AppleBridgeCore"

fmt-swift:
    swiftformat {{_swift-sources}} {{_swift-exclude}}

fmt-check-swift:
    swiftformat --lint {{_swift-sources}} {{_swift-exclude}}
```

- [ ] **Step 3: Apply formatting**

Run: `just fmt-swift`  
Expected: reformats hand-written Swift; does not touch `apple_bridge_core.swift`

- [ ] **Step 4: Verify lint mode**

Run: `just fmt-check-swift`  
Expected: exit 0, "0/… files require formatting"

- [ ] **Step 5: Verify tests still pass**

Run: `just test-swift`  
Expected: all Swift tests pass

- [ ] **Step 6: Commit**

```bash
git add .swiftformat justfile AppleBridge/ AppleBridgeTests/
git commit -m "chore: add SwiftFormat config and fmt-check-swift recipe"
```

---

### Task 3: SwiftLint config + `lint-swift`

**Files:**
- Create: `.swiftlint.yml`
- Modify: `justfile`
- Modify: Swift sources (lint fixes only — no behavior changes)

- [ ] **Step 1: Create `.swiftlint.yml`**

```yaml
included:
  - AppleBridge
  - AppleBridgeTests
excluded:
  - AppleBridgeCore
  - AppleBridge/Services/apple_bridge_core.swift
line_length:
  warning: 120
  error: 160
  ignores_urls: true
  ignores_function_declarations: true
type_body_length:
  warning: 300
identifier_name:
  min_length:
    warning: 2
  excluded:
    - id
```

- [ ] **Step 2: Add `lint-swift` to `justfile`**

```just
lint-swift:
    swiftlint lint --strict --quiet
```

- [ ] **Step 3: Run and fix violations**

Run: `just lint-swift`  
Expected: exit 0 after fixing any violations (prefer `// swiftlint:disable:next` only when a rule is genuinely wrong for generated-adjacent glue — avoid blanket disables)

- [ ] **Step 4: Verify**

Run: `just fmt-check-swift && just lint-swift && just test-swift`  
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add .swiftlint.yml justfile AppleBridge/ AppleBridgeTests/
git commit -m "chore: add SwiftLint config and lint-swift recipe"
```

---

### Task 4: `ci-macos`, `ci`, and macOS CI workflow

**Files:**
- Modify: `justfile`
- Create: `.github/workflows/ci-macos.yml`

- [ ] **Step 1: Add macOS guard and CI recipes to `justfile`**

```just
# macOS CI steps (no host guard — used by GitHub Actions macos runner)
ci-macos-steps: _rust-workspace
    just fmt-check-swift
    just lint-swift
    just test-swift
    just build-rust

# Local entry point; skips gracefully off-macOS
ci-macos:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! uname | grep -qi darwin; then
      echo "skipped: ci-macos requires macOS" >&2
      exit 0
    fi
    just ci-macos-steps

ci:
    just ci-rust
    @uname | grep -qi darwin && just ci-macos-steps || echo "skipped: ci-macos (not macOS)"
```

Note: workflow runs `just ci-macos` on the macOS runner (always executes steps). `just ci` calls `ci-macos-steps` directly on macOS to avoid the guard script overhead.

- [ ] **Step 2: Verify locally**

Run: `just ci-macos`  
Expected: fmt-check, lint, test-swift, build-rust all pass

Run: `just ci`  
Expected: full suite passes on macOS

- [ ] **Step 3: Create `.github/workflows/ci-macos.yml`**

```yaml
name: macOS CI

on:
  push:
    branches: [main]
    paths:
      - "AppleBridge/**"
      - "AppleBridgeTests/**"
      - "project.yml"
      - "rust/**"
  pull_request:
    paths:
      - "AppleBridge/**"
      - "AppleBridgeTests/**"
      - "project.yml"
      - "rust/**"

concurrency:
  group: macos-ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  macos:
    runs-on: macos-15
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - uses: dtolnay/rust-toolchain@master
        with:
          toolchain: "1.85"

      - uses: extractions/setup-just@v2

      - name: Install Swift hygiene tools
        run: brew install swiftformat swiftlint

      - name: macOS CI
        run: just ci-macos
        env:
          TZ: UTC
```

- [ ] **Step 4: Commit**

```bash
git add justfile .github/workflows/ci-macos.yml
git commit -m "chore: add macOS CI workflow and just ci-macos/ci recipes"
```

---

### Task 5: Path detection + pre-push hook

**Files:**
- Create: `scripts/ci/paths.sh`
- Create: `scripts/ci/pre-push-verify.sh`
- Create: `.githooks/pre-push`
- Create: `.githooks/README.md`

- [ ] **Step 1: Create `scripts/ci/paths.sh`**

```bash
#!/usr/bin/env bash
# Classify changed files between two refs.
# Usage: scripts/ci/paths.sh <base_ref> <head_ref>
# Exports: PATHS_RUST_CHANGED=0|1  PATHS_SWIFT_CHANGED=0|1

set -euo pipefail

BASE_REF="${1:?base ref required}"
HEAD_REF="${2:?head ref required}"

PATHS_RUST_CHANGED=0
PATHS_SWIFT_CHANGED=0

changed_files="$(git diff --name-only "${BASE_REF}"..."${HEAD_REF}" 2>/dev/null || git diff --name-only "${BASE_REF}" "${HEAD_REF}")"

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    rust/*)
      PATHS_RUST_CHANGED=1
      PATHS_SWIFT_CHANGED=1
      ;;
    AppleBridge/*|AppleBridgeTests/*|project.yml)
      PATHS_SWIFT_CHANGED=1
      ;;
  esac
done <<< "$changed_files"

export PATHS_RUST_CHANGED PATHS_SWIFT_CHANGED
```

- [ ] **Step 2: Create `scripts/ci/pre-push-verify.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BASE_REF="${CI_BASE_REF:-origin/main}"
STRICT="${CI_STRICT:-}"

run_verify() {
  local label="$1"
  shift
  echo "pre-push verify: ${label}"
  if "$@"; then
    return 0
  fi
  if [[ -n "$STRICT" ]]; then
    echo "pre-push verify: FAILED (CI_STRICT=1 — blocking push)" >&2
    return 1
  fi
  echo "pre-push verify: FAILED (advisory — push will continue; set CI_STRICT=1 to block)" >&2
  return 0
}

# Resolve range from pre-push stdin when invoked as hook
HEAD_REF="HEAD"
REMOTE_OID=""
while read -r _local_ref local_oid _remote_ref remote_oid; do
  HEAD_REF="$local_oid"
  REMOTE_OID="$remote_oid"
done

if [[ "$REMOTE_OID" == "0000000000000000000000000000000000000000" ]]; then
  # New branch: compare commits on branch vs base
  MERGE_BASE="$(git merge-base "$BASE_REF" "$HEAD_REF" 2>/dev/null || echo "$BASE_REF")"
  source "$REPO_ROOT/scripts/ci/paths.sh" "$MERGE_BASE" "$HEAD_REF"
else
  source "$REPO_ROOT/scripts/ci/paths.sh" "$REMOTE_OID" "$HEAD_REF"
fi

if [[ "$PATHS_RUST_CHANGED" -eq 0 && "$PATHS_SWIFT_CHANGED" -eq 0 ]]; then
  echo "pre-push verify: no CI paths changed — skipping"
  exit 0
fi

if [[ "$PATHS_RUST_CHANGED" -eq 1 ]]; then
  run_verify "rust (ci-rust)" just ci-rust || exit $?
fi

if [[ "$PATHS_SWIFT_CHANGED" -eq 1 ]]; then
  run_verify "swift fmt" just fmt-check-swift || exit $?
  run_verify "swift lint" just lint-swift || exit $?
  run_verify "swift test" just test-swift || exit $?
fi

echo "pre-push verify: done (build-rust skipped — runs in macOS CI)"
```

- [ ] **Step 3: Create `.githooks/pre-push`**

```sh
#!/bin/sh
set -eu

REPO_ROOT="$(git rev-parse --show-toplevel)"

# 1. Fast CI verify (path-aware)
if [ -x "$REPO_ROOT/scripts/ci/pre-push-verify.sh" ]; then
  "$REPO_ROOT/scripts/ci/pre-push-verify.sh" || exit $?
fi

# 2. Optional local agent review (if installed)
REVIEW_SCRIPT="$REPO_ROOT/local/review/bin/review.sh"
if [ -x "$REVIEW_SCRIPT" ]; then
  if [ -n "${REVIEW_STRICT:-}" ]; then
    exec "$REVIEW_SCRIPT" --hook --strict
  fi
  exec "$REVIEW_SCRIPT" --hook
fi
```

- [ ] **Step 4: Create `.githooks/README.md`**

```markdown
# Git hooks

```sh
git config core.hooksPath .githooks
```

## pre-push

Runs path-aware CI verify, then optional local agent review (`local/review/`) if installed.

| Variable | Effect |
|----------|--------|
| `CI_STRICT=1` | verify failures block push |
| `REVIEW_STRICT=1` | review failures block push |
| default | advisory — warn, push proceeds |
```

- [ ] **Step 5: Make scripts executable and smoke-test**

```bash
chmod +x scripts/ci/paths.sh scripts/ci/pre-push-verify.sh .githooks/pre-push
git config core.hooksPath .githooks
scripts/ci/paths.sh origin/main HEAD
# Expect PATHS_* exports matching your working tree changes
./scripts/ci/pre-push-verify.sh
```

- [ ] **Step 6: Commit**

```bash
git add scripts/ci/ .githooks/
git commit -m "chore: add path-aware pre-push verify hook"
```

---

### Task 6: README refresh

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace `README.md`**

Replace entire file with (badges show green after workflows run on `main` at least once):

```markdown
# Apple Bridge

Native macOS app exposing Apple platform capabilities through a local, authenticated MCP server. A generic bridge between Apple frameworks and external clients—AI agents, desktop apps, scripts, and automation tools—without embedding application-specific logic.

**Status:** Menu bar shell, Rust MCP/HTTP server (health + bearer auth), Swift ↔ Rust via UniFFI. V1 provider: EventKit (Reminders + Calendar).

## CI status

[![Rust CI](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-rust.yml/badge.svg)](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-rust.yml)
[![macOS CI](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-macos.yml/badge.svg)](https://github.com/rcanoff/apple-bridge/actions/workflows/ci-macos.yml)

Rust CI runs on Linux when `rust/` changes (fmt, clippy, tests). macOS CI runs when Swift, Xcode project, or Rust bindings change (SwiftFormat, SwiftLint, tests, UniFFI build).

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
- Before opening a PR: `just ci`
- Install hooks: `git config core.hooksPath .githooks`
- Agent rules: `AGENTS.md`
- Deep reference: `docs/conventions.md`, `docs/architecture-bootstrap-guide.md`, `docs/prd.md`
```

(Fenced block above is the complete `README.md` content.)

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: refresh README with CI badges and contributor guide"
```

---

### Task 7: Update `docs/conventions.md` and `AGENTS.md`

**Files:**
- Modify: `docs/conventions.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Add Swift hygiene to `docs/conventions.md` § Formatting and lint**

Under `### Swift`, replace bullet list with:

```markdown
### Swift

- Config: `.swiftformat`, `.swiftlint.yml` at repo root
- Exclude generated: `AppleBridge/Services/apple_bridge_core.swift`, `AppleBridgeCore/`
- Run before commit:

```sh
just fmt-check-swift
just lint-swift
just test-swift
```
```

- [ ] **Step 2: Add CI section to `docs/conventions.md` before Commit and PR hygiene**

```markdown
## CI

| Workflow | Runner | Path filter |
|----------|--------|-------------|
| Rust CI | `ubuntu-latest` | `rust/**` |
| macOS CI | `macos-15` | `AppleBridge/**`, `AppleBridgeTests/**`, `project.yml`, `rust/**` |

Local parity: `just ci`. Pre-push runs a fast subset (skips `build-rust`); install via `git config core.hooksPath .githooks`.
```

- [ ] **Step 3: Update `AGENTS.md` tooling section**

Add after existing `just` recipes:

```sh
just fmt-check-swift  # SwiftFormat lint
just lint-swift       # SwiftLint strict
just ci-rust          # Rust CI subset
just ci-macos         # macOS CI subset
just ci               # Full local CI parity
```

Update verification matrix row for any change to:

`| Any PR | PR 2+: `just ci` (or workflow equivalents on GitHub) |`

- [ ] **Step 4: Commit**

```bash
git add docs/conventions.md AGENTS.md
git commit -m "docs: document CI pipelines and Swift hygiene in conventions"
```

---

### Task 8: Final verification

- [ ] **Step 1: Full local verify**

```bash
just ci
```

Expected: Rust lint+test, Swift fmt+lint+test, build-rust all pass

- [ ] **Step 2: Push branch and confirm workflows**

```bash
git push -u origin chore/ci-pipelines-readme
```

Open PR against `main`. Confirm:

- Both workflows appear on the PR
- Rust CI runs (this PR touches `rust/` only if… actually this PR touches many paths — both should run)
- macOS CI runs and passes

- [ ] **Step 3: Confirm README badges**

After first merge to `main` (or first workflow run on branch), badges in README show pass/fail.

---

## Spec Coverage Check

| Spec section | Task |
|--------------|------|
| `ci-rust.yml` Linux | Task 1 |
| `ci-macos.yml` path-filtered | Task 4 |
| SwiftFormat + SwiftLint | Tasks 2–3 |
| `just ci-*` recipes | Tasks 1, 4 |
| Pre-push fast subset | Task 5 |
| README + badges | Task 6 |
| Conventions / AGENTS | Task 7 |
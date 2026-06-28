# AGENTS.md — Apple Bridge

Source of truth for agent behavior, skills, verification, and branch naming. Keep the working directory at the repo root.

## At a glance

| Question | Answer |
|----------|--------|
| **Platform** | macOS **26.0+** only, **arm64** only |
| **Purpose** | Generic Apple framework bridge over local authenticated MCP |
| **Runtime** | Menu bar agent app; MCP on `127.0.0.1` (default port `3020`) |
| **Stack** | SwiftUI shell + Rust core (`apple_bridge_core`) via UniFFI |
| **V1 provider** | EventKit (Reminders + Calendar) |
| **PRD** | `docs/prd.md` |
| **Architecture** | `docs/architecture-bootstrap-guide.md` |
| **Conventions** | `docs/conventions.md` |
| **Plans / specs** | `docs/superpowers/` (local; not tracked in git by default) |

## Architecture (summary)

```
MenuBarExtra → AppStore / ServerStore → ServerService → Rust ServerHandle
                                              ↓
                                    ProviderBridge (UniFFI callback)
                                              ↓
                              EventKitProvider / MapKitProvider / …
```

| Layer | Owns |
|-------|------|
| **Swift** | UI, permissions, Keychain, thin Apple adapters |
| **Rust** | MCP HTTP server, auth, routing, config validation, tests |

Full process model, bootstrap steps, and endpoint design live in the architecture guide — not here.

## Hard rules

- **Localhost only** — bind `127.0.0.1`; never `0.0.0.0` by default.
- **Bearer auth required** on MCP routes once auth ships; never log tokens.
- **Apple is source of truth** — no app database; frameworks own user data.
- **Thin Swift providers** — no business logic, auth, or routing in `Providers/`.
- **Rust owns server behavior** — validation, MCP routing, and typed errors stay in `apple_bridge_core`.
- **Never edit generated code** — `AppleBridgeCore/`, `apple_bridge_core.swift`.
- **Follow `docs/conventions.md`** for naming, libraries, formatting, errors, concurrency, and testing.

### Framework fidelity (providers / MCP payloads)

Apple Bridge is a **bridge**, not a converter. Swift providers call Apple frameworks; MCP exposes the result as JSON. The only allowed transformation is **mechanical serialization** — not semantic reshaping.

**Allowed (serialization only):**

- Apple object/property → JSON value (types that cannot cross JSON boundaries)
- `nil` / missing optional → JSON `null` (never substitute `""`, `0`, or `false` for absent Apple values)
- `Date` → ISO 8601 string; `DateComponents` → structured object preserving calendar fields
- `URL` → string; `Data` / opaque buffers → base64 when the framework exposes them as data
- Nested framework objects → nested JSON objects (same depth Apple provides — do not flatten)
- JSON key `snake_case` encoding of Apple API names (e.g. `calendarItemIdentifier` → `calendar_item_identifier`) — naming convention only, not renaming semantics

**Forbidden — reject in design, spec, implementation, and review:**

- **Field subsetting** — omitting Apple properties from read responses because a capability is “not shipped yet” or to keep PRs small
- **Renamed semantics** — aliases that hide Apple names (e.g. `id` for `calendar_item_identifier`, `list_id` for `calendar.calendar_identifier`, `completed` for `is_completed`) unless the Apple API itself uses that name
- **Invented fields** — keys that do not correspond to an Apple property or standard serialization envelope
- **Derived / computed fields** — aggregations, defaults, filtering, sorting, or business logic applied to framework data
- **Conditional omission** — dropping keys when “empty” (e.g. omit `notes` when nil) unless Apple’s API treats absent and empty identically and the spec documents the exception
- **Custom DTOs** — hand-maintained “read models” that are not exhaustive projections of the framework type (protocol test seams may use fakes that implement the same **full** shape)

**Specs and plans:** If a spec or plan proposes a partial payload, incremental field rollout, or “minimal demo shape,” **do not implement it**. Revise the spec to full faithful projection or escalate to the user. PR 3a/3a1 minimal reminder JSON is **legacy debt** corrected by PR 3a2.

**Read tools:** All read endpoints returning the same framework type must return the **same complete JSON shape** (e.g. `list_reminders` items ≡ `get_reminder` object ≡ each element’s fidelity).

Details: `docs/conventions.md` § JSON and payloads.

## Branch naming

Match existing repo conventions:

| Prefix | Use | Examples |
|--------|-----|----------|
| `feat/` | User-facing or architectural features | `feat/pr1-menu-bar-shell`, `feat/pr2a-rust-uniffi-skeleton` |
| `chore/` | Tooling, docs, agent setup, config | `chore/xcode-mcp-config`, `chore/agent-setup-and-conventions` |

**Pattern:** `<prefix>/<short-kebab-description>`

- Include PR phase when work maps to a planned PR: `feat/pr2b-http-health`
- One concern per branch; keep diffs reviewable
- Branch from `main` unless a spec says otherwise

## Skills

Invoke the **using-superpowers** skill at the start of every conversation before other work.

### Required skills

Before editing Swift files under `AppleBridge/` or `AppleBridgeTests/`:

1. Read and follow **swiftui-pro**
2. For tests (`AppleBridgeTests/`): also **swift-testing-pro**
3. For concurrency changes (`@MainActor`, `@Observable`, async/await, FFI): also **swift-concurrency-pro**

Do not write or review Swift code without loading these skills first.

Before editing Rust files under `rust/` (once `rust/Cargo.toml` exists — PR 2+):

1. Read and follow **rust-best-practices**
2. Read `rust/AGENTS.md` — project overrides supersede the skill where they conflict
3. Read `docs/conventions.md` for UniFFI, crates, and test seams

Do not write or review Rust code without loading these first.

### Process skills (pick first)

| Skill | When |
|-------|------|
| **brainstorming** | New features, behavior changes, or design decisions before coding |
| **writing-plans** | Multi-step work that needs a plan file under `docs/superpowers/plans/` |
| **executing-plans** | Implementing an approved plan in a separate session with checkpoints |
| **subagent-driven-development** | Executing plan tasks with subagents in the current session |
| **test-driven-development** | Any feature or bugfix — write failing tests first |
| **systematic-debugging** | Bugs, test failures, or unexpected runtime behavior |
| **verification-before-completion** | Before claiming work is done, fixed, or passing |
| **using-git-worktrees** | Feature work that needs isolation from the current workspace |

### Domain skills (by code area)

| Skill | When |
|-------|------|
| **swiftui-pro** | Reading, writing, or reviewing SwiftUI views and app structure |
| **swift-testing-pro** | Swift Testing suites in `AppleBridgeTests/` |
| **swift-concurrency-pro** | `@MainActor`, `@Observable`, `@concurrent`, async/await, FFI isolation |
| **rust-best-practices** | Rust in `rust/` once `rust/Cargo.toml` exists — apply `rust/AGENTS.md` overrides |

No SwiftData in this project — do not invoke **swiftdata-pro**.

Only invoke skills named in the tables above. Do not reference skill names that are not installed in your environment.

### Completion skills

| Skill | When |
|-------|------|
| **finishing-a-development-branch** | Implementation complete; decide merge/PR/cleanup |
| **requesting-code-review** | Major feature complete, before merge |
| **receiving-code-review** | Acting on review feedback — verify before implementing |

For implementation, review, and design work, use the process skills above (especially **test-driven-development**, **verification-before-completion**, and **requesting-code-review**). Do not assume optional bundled skills are available.

### Review triage (when asked to check a review)

Keep the response short. The user can ask for code walkthroughs or examples separately.

Use **one table** — no separate lists, no code blocks, no patch sketches unless asked.

| # | Topic | Agree? | Note |
|---|-------|--------|------|
| 1 | One short phrase on what the comment is about | Yes / No | Only if No — why you disagree |

- **#** — index matching the review (or sequential if unnumbered)
- **Topic** — ~8–15 words; name the issue and where it bites, but keep each cell on one line
- **Agree?** — `Yes` or `No` only
- **Note** — **only when `No`**; omit the column value (leave empty) for `Yes`

Do **not** include by default: long explanations, architecture essays, code citations, or re-stating the review verbatim. Add detail only when the user asks.

## Tooling

### XcodeBuildMCP (preferred for Apple platform work)

Use **XcodeBuildMCP** tools instead of raw `xcodebuild` shell commands when available:

- Call `session_show_defaults` at the start of a build/run/test session
- Use `build_run_sim` / project build tools for compile and test workflows
- Use `discover_projs` only when session defaults are missing or wrong

### Code review

Do **not** run review yourself — no review skill, no reviewer subagents, no hand-written findings.

Use the repo review runner:

```sh
just review              # Grok + Codex (default)
just review --codex-only # Codex only
just review --grok-only  # Grok only
just review-strict       # same agents; exit non-zero on failure
```

Reviews are written under `docs/reviews/`. Act on feedback with **receiving-code-review**; triage with the table in § Review triage.

### Shell commands

Available on this branch:

```sh
just test-swift     # xcodebuild test (macOS)
just test-all       # test-swift; adds test-rust when rust/Cargo.toml exists
just review         # multi-agent code review (see § Code review)
```

After the Rust workspace lands (PR 2+, requires `rust/Cargo.toml`):

```sh
just fmt-rust       # cargo fmt --all
just fmt-check-rust # cargo fmt --all --check (EOF newline + formatting)
just test-rust      # TZ=UTC cargo test
just lint-rust      # fmt-check + clippy -D warnings
just build-rust     # XCFramework + UniFFI bindings
just fmt-check-swift  # SwiftFormat lint
just lint-swift       # SwiftLint strict
just ci-rust          # Rust CI subset
just ci-macos         # macOS CI subset
just ci               # Full local CI parity
```

Regenerate Xcode project after `project.yml` changes:

```sh
xcodegen generate
```

## Verification matrix

| Change type | Minimum validation |
|-------------|-------------------|
| Any PR | `just ci` (or equivalent GitHub workflow checks) |
| Swift model / mapper | Swift Testing unit tests |
| SwiftUI / store | Build + unit tests; manual menu bar smoke when UX changes |
| Permission flow | Unit tests with protocol mocks; manual smoke for system dialog |
| Rust module | PR 2+: `just lint-rust && just test-rust` (`lint-rust` includes `fmt-check-rust`) |
| UniFFI API change | PR 2+: `just build-rust`, fix Swift call sites, `just test-all` |
| MCP / HTTP | PR 2+: Rust integration tests + manual `curl /health` smoke |

Always run with `TZ=UTC`. EventKit permission dialogs and live framework calls are **manual only** — mock via protocols in CI.

## Commit gate

Do **not** commit unless the user explicitly says the work is ready to commit.

## Reference

| Area | Path |
|------|------|
| Product scope | `docs/prd.md` |
| Architecture & bootstrap | `docs/architecture-bootstrap-guide.md` |
| Naming, libs, dev standards | `docs/conventions.md` |
| PR specs / plans | `docs/superpowers/specs/`, `docs/superpowers/plans/` |
| Xcode project | `project.yml` → `AppleBridge.xcodeproj` |

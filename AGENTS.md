# AGENTS.md — ABridge

Source of truth for agent behavior, skills, verification, and branch naming. Keep the working directory at the repo root.

## At a glance

| Question | Answer |
|----------|--------|
| **Platform** | macOS **26.0+** only, **arm64** only |
| **Purpose** | Generic Apple framework bridge over local authenticated MCP |
| **Runtime** | Menu bar agent app; MCP on `127.0.0.1` (default port `3020`) |
| **Stack** | SwiftUI shell + Rust core (`abridge_core`) via UniFFI |
| **Providers** | EventKit, Contacts, MapKit, Core Location, Vision, Notes |
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
| **Rust** | MCP HTTP server, auth, routing, config validation, agent-facing shapes, search ranking, tests |

**Notes is Rust-native.** Apple Notes has no public framework, so the `notes` provider lives in `rust/abridge_core/src/notes/` and never reaches `ProviderBridge`: reads open `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite` with `SQLITE_OPEN_READ_ONLY` in one read transaction and decode gzip/zlib protobuf bodies and tables. Writes run a fixed JXA script through `/usr/bin/osascript`, with user input only as JSON on the script's stdin (`osascript -e` still holds the fixed script; the payload is not an argument), so Notes performs every mutation and owns iCloud sync. Rust may spawn `/usr/bin/osascript` for writes and `/usr/bin/sips` for image renditions, each with a timeout. Swift only registers the provider, gates it on Full Disk Access and Automation, and shows the Permissions card. Never write to the Notes store directly.

Full process model, bootstrap steps, and endpoint design live in the architecture guide — not here.

## Hard rules

- **Localhost only** — bind `127.0.0.1`; never `0.0.0.0` by default.
- **Bearer auth required** on MCP routes once auth ships; never log tokens.
- **Apple is source of truth** — no ABridge user-data database; Apple frameworks or apps own user data.
- **Provider boundaries** — framework-backed providers use thin Swift adapters. Providers for Apple apps without a public framework (currently Notes) may read the app's store read-only and write through its scripting interface.
- **Thin Swift providers** — call Apple frameworks and serialize their objects; keep agent-facing shaping, business logic, auth, and routing out of `Providers/`.
- **Rust owns server behavior** — validation, MCP routing, response shaping, search ranking, and typed errors stay in `abridge_core`.
- **Write-safety guards are server behavior** — for no-public-framework providers, Rust may enforce safe scripting writes without taking on client business logic. Serialize Notes writes and poll the store for each write's specific outcome. An update confirms the note body (`note_data`), not a modification-date change alone. Fail `write_unconfirmed` if that outcome does not appear. `write_unconfirmed`, and an osascript timeout, means the change may have happened, so check before retrying. `notes_delete_note` checks live in the script and refuses notes already in Recently Deleted. Success sets `deletion` to `recently_deleted`; permanent deletion is not available. `notes_create_folder` prechecks Notes' sibling-name rule and returns `folder_name_taken` with the existing folder's identifier. `notes_delete_folder` refuses Recently Deleted, smart folders, the account default folder, and folders that still hold notes or subfolders. The script rechecks emptiness immediately before deleting and returns `folder_not_empty` if the folder now holds notes or subfolders, then confirms the folder is gone or marked for deletion.
- **Notes permissions** — require `com.apple.security.automation.apple-events` and `NSAppleEventsUsageDescription` for Automation; request Full Disk Access through System Settings.
- **Never edit generated code** — `ABridgeCore/`, `abridge_core.swift`.
- **Follow `docs/conventions.md`** for naming, libraries, formatting, errors, concurrency, and testing.

### Agent-shaped responses

MCP responses carry what an agent reads, links, and acts on. Apply these rules to every provider:

- **Useful fields:** keep content, actionable identifiers, and context. Leave out framework/store internals, sync bookkeeping, UI state, internal UUIDs, invalid sentinels such as `-1`, and raw binary. Derived names, paths, counts, snippets, and search evidence belong in the response when they help the caller.
- **Omission:** omit null, false, and empty values. Tool descriptions state that an absent key means null, false, or empty. Keep false explicitly when it carries an outcome, such as diagnostics `success` and `logging_enabled`.
- **Summary/detail:** list and search return compact summaries sufficient to select an item and call get/update. `get_*` and writes that return an object use its detail shape. Reuse the same summary or detail shape for a given type across tools; search adds ranking evidence.
- **Rust shaping:** Swift serializes framework objects without agent-specific shaping. `agent_shape/` compacts those payloads in `mcp/mod.rs` before delivery and shapes diagnostics. Its `prepare` step may rewrite requests, such as fetching contacts with `list_contacts` for Rust fuzzy ranking. Notes uses `notes/shape.rs` directly; `notes/project.rs` stays internal to write confirmation.
- **Markdown text:** return rich text bodies as Markdown, including Notes formatting, tables, checklists, and `[title](attachment:<id>)` links. Inline hashtags, mentions, and Math results are text. Notes rendering lives in `notes/markdown.rs`. Create and update `body` is that same Markdown (`notes/markdown_html.rs` converts it). HTML in the body is converted. Warnings name every converted HTML tag and every removed HTML tag. Headings are stored as bold and read back as `#` / `##` headings; headings beyond `##` read back as bold. A blank line between blocks becomes an empty Notes line (Notes has no paragraph spacing), and Notes may add a trailing slash to a bare domain. Creating `- [ ]` / `- [x]` stores ordinary bullets, so a later `notes_update_note` can replace that text. `notes_update_note` replaces the whole body and refuses (`body_would_drop_content`) when a native checklist or a non-table attachment would be dropped. It also refuses `body_unavailable` when the current body is missing, not downloaded, past the inflate limit, or not a note protobuf, and `note_changed` when the live note's modification date or attachment count differs from the snapshot. An identical body succeeds without waiting. Notes with files or checklists cannot have their text edited through scripting without losing them, and nothing is changed.
- **Readable fields:** contact labels are plain words (`mobile`, `home fax`); a custom label is unchanged. Event notes are plain text or Markdown. Event start and end, including each occurrence, are local wall time with a numeric offset in the event time zone, or the server Mac's time zone when the event has none (not the caller's), plus `time_zone` when known. All-day events return `start_date` and `end_date` as calendar dates `YYYY-MM-DD`. `end_date` is exclusive (the day after the last day). Each calendar day is that serialized instant converted into the event's time zone, or this Mac's time zone when the event has none. Pass an absolute time such as `2026-10-26T09:00:00-04:00`, or wall time `2026-10-26T09:00:00` with `time_zone` `America/New_York`. All-day events use `2026-10-26`. The server does not treat its clock or time zone as the caller's. Reminder due and start dates are `YYYY-MM-DD` when date-only. A time whose components include `time_zone` is local wall time with that zone's offset. A time with no components `time_zone` is floating wall time with no offset and `floating: true` (that clock time wherever the person is, not the server's zone). The components' `time_zone` stamps a zoned time. The reminder `time_zone` does not. A due time written without a components `time_zone` stays floating. A title search for events with no dates covers 1 year before through 2 years after the server Mac's current time. Event detail keeps `event_identifier`. Calendar and reminder-list `source` is `{source_identifier, title, type}`.
- **List paging:** `eventkit_events_list_events`, `eventkit_reminders_list_reminders`, `contacts_list_contacts`, and `contacts_list_groups` default to 50 items (maximum 200). `offset` pages the shaped list.
- **Fuzzy search:** local text search uses shared `crate::fuzzy` (`fuzzy.rs`, `nucleo-matcher`). Space-separated terms must all match inside one word (a run of letters or digits; a hyphen or apostrophe stays inside the word), case-insensitive and accent-insensitive (`acao` matches `ação`). `"buy milk"` is one exact phrase (spaces stay). `'term` is an exact substring of one word and does not quote spaces. `^term` and `term$` are word anchors, `!term` excludes a match, and `term | term` matches either. An unmatched `"` is ignored. Weighted fields, per-line matching for long text, best-first hits with `score` and `matches: [{field, excerpt}]`, matched characters marked with `«»`. Apple predicates still filter dates, calendars, and completion. MapKit, Core Location, and Vision do not use fuzzy queries.
- **Binary content:** send files and photos as MCP `image` or embedded `resource` content after the JSON text item, never base64 inside the JSON payload. Contact list/search summaries contain no image bytes. Apply the image rendition and file limits in `docs/conventions.md`.

**Notes discovery:** `notes_list_folders` supplies `account {identifier, name}`; there is no separate account-list tool. It leaves out folders Notes has not downloaded from iCloud yet. Tools that take `folder_identifier` also take `folder_path` (that `path`, case-insensitive exact match); pass exactly one, and `account_identifier` when the path exists in more than one account. `notes_get_note`, `notes_update_note`, `notes_move_note`, and `notes_delete_note` take `note_title` (exact, case-insensitive, live notes only) instead of `note_identifier`. A title in Recently Deleted matches only when the folder is that folder. Several title matches return `note_title_ambiguous`. Default note lists hide Recently Deleted and notes awaiting download. `notes_search_notes` defaults to 20 hits and caches its in-memory text index until `NoteStore.sqlite` or its `-wal` sibling changes. A match on attachment text also includes `attachment_identifier` and `attachment_title`.

Field selection, Markdown, search syntax, binary limits, and test requirements: `docs/conventions.md` § JSON and payloads and § Testing.

### MCP tool names

A tool's name is its whole external identity: `tools/list` advertises it, `tools/call` resolves only that exact string, and the usage audit records it. Names live in the `TOOL_*` constants in `rust/abridge_core/src/tools/mod.rs`.

- **Shape:** `<provider>_<domain>_<operation>`, or `<provider>_<operation>` when the provider has no domain (`eventkit_reminders_list_lists`, `mapkit_search_places`). The name is built from the `ToolDefinition`'s `provider` and `operation`, the pair Swift dispatches on, so tool, route, and Swift handler share one vocabulary.
- **Characters:** lowercase ASCII letters and digits joined by single underscores, at most 50 characters. Clients prefix the server name (`mcp__abridge__<tool>` in Claude Code, `abridge__<tool>` in Grok), and Claude Code rejects prefixed names over 64 characters.
- **Provider:** the Apple framework whose API serves the call (`CLLocationManager` → `corelocation`, `MKLocalSearch` → `mapkit`). The tool's capability ID uses the same provider prefix (`corelocation.read`). For an Apple app without a public framework, use the app name (`notes`, `notes_list_notes`, `notes.read`); Rust-native Notes uses the same provider/operation pair without Swift dispatch.
- **Verbs:** `get_<noun>` returns one item, and every fetch-by-identifier tool uses it (`get_event`, `get_place`); `list_<nouns>` enumerates; `search_<nouns>` filters; `create_`, `update_`, `delete_`, `move_` mutate; `set_<noun>_<field>` replaces a collection field.
- **Vision:** tools take the Apple request's name (`RecognizeDocumentsRequest` → `recognize_documents`, `DetectFaceLandmarksRequest` → `detect_face_landmarks`).
- **One tool per Apple operation:** variants of one API are arguments (`symbologies` on `vision_detect_barcodes`), never sibling tools.
- **Renames are clean cutovers:** the constant, operation, Swift handler, tests, and docs change together, and the old name stops resolving. No aliases, no legacy name resolution.

Unit tests in `rust/abridge_core/src/tools/mod.rs` enforce shape, characters, length, the provider-scoped capability, and uniqueness.

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

When a skill named here is installed, read it before the work it covers. Skip a skill that is not installed.

When **using-superpowers** is installed, invoke it at the start of the conversation before other work.

### Required skills

Before editing Swift files under `ABridge/` or `ABridgeTests/`:

1. Read and follow **swiftui-pro**
2. For tests (`ABridgeTests/`): when **swift-testing-pro** is installed, read it too
3. For concurrency changes (`@MainActor`, `@Observable`, async/await, FFI): when **swift-concurrency-pro** is installed, read it too

Before editing Rust files under `rust/`:

1. When **rust-best-practices** is installed, read it
2. Read `rust/AGENTS.md` — project overrides supersede that skill where they conflict
3. Read `docs/conventions.md` for UniFFI, crates, and test seams

### Process skills (pick first)

When the skill is installed:

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
| **swift-testing-pro** | Swift Testing suites in `ABridgeTests/` |
| **swift-concurrency-pro** | `@MainActor`, `@Observable`, `@concurrent`, async/await, FFI isolation |
| **rust-best-practices** | When installed: Rust in `rust/` — apply `rust/AGENTS.md` overrides |

No SwiftData in this project.

Only invoke skills named in the tables above. Do not reference skill names that are not installed in your environment.

### Completion skills

When the skill is installed:

| Skill | When |
|-------|------|
| **finishing-a-development-branch** | Implementation complete; decide merge/PR/cleanup |
| **requesting-code-review** | Major feature complete, before merge |
| **receiving-code-review** | Acting on review feedback — verify before implementing |

For implementation, review, and design work, use the process skills above when they are installed (especially **test-driven-development**, **verification-before-completion**, and **requesting-code-review**).

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

Run the repo review runner:

When the user explicitly asks for a model review, run that review as requested. It sits alongside `just review`.

Without that request, leave review to the runner: do not start a review skill, a reviewer subagent, or hand-written findings.

```sh
just review              # Grok + Codex (default)
just review --codex-only # Codex only
just review --grok-only  # Grok only
just review-strict       # same agents; exit non-zero on failure
```

Reviews are written under `docs/reviews/`. When **receiving-code-review** is installed, use it to act on feedback. Triage with the table in § Review triage.

### GitHub issues

Use **`gh`** from the repo root (`rcanoff/abridge`). When the user asks to create an issue, follow this workflow.

**Templates:** `docs/github-issue-templates/`

| File | Use |
|------|-----|
| `standalone.md` | Single issue, no parent epic |
| `epic.md` | Parent tracking a feature area |
| `subtask.md` | Child of an epic — one small PR each |

**Labels:**

| Label | Apply to |
|-------|----------|
| `enhancement` | All feature work (default) |
| `epic` | Parent epics only |
| `subtask` | Sub-issues of an epic |

Do **not** list child issues in markdown tables on the epic body. Use GitHub **native sub-issues** (task list on the epic). Put merge order as a numbered list of titles in the epic body.

**Create a standalone issue:**

```sh
gh issue create --title "Short title" --label enhancement --body-file docs/github-issue-templates/standalone.md
```

(Edit the template content into a temp file first; fill all sections before creating.)

**Create an epic + subtasks:**

1. Create epic: `gh issue create --title "Epic: …" --label enhancement --label epic --body-file <epic-body.md>`
2. Create each subtask: `gh issue create --title "…" --label enhancement --label subtask --body-file <subtask-body.md>`
3. Link subtasks to the epic (use integer issue `id` from `gh api repos/rcanoff/abridge/issues/<N> --jq .id`):

```sh
gh api -X POST /repos/rcanoff/abridge/issues/<EPIC_NUMBER>/sub_issues -F sub_issue_id=<CHILD_ID>
```

Add children in merge order (first subtask first). Sub-issue bodies must **not** include a `## Parent` section — GitHub shows the parent on the issue. Use `## Depends on` for sibling ordering instead.

**Subtask sizing:** One reviewable PR per subtask. Split Rust pipeline vs Swift UI vs MCP tool registration when a feature spans layers.

**Issue body quality:** Pull requirements from `docs/prd.md`; include scope, out-of-scope, acceptance criteria, branch name, and verification commands. Remove temp body files after `gh issue create`.

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
just release-build X.Y.Z  # Signed + notarized DMG and Sparkle appcast (env: scripts/release.sh header)
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
| GitHub issue templates | `docs/github-issue-templates/` |
| Xcode project | `project.yml` → `ABridge.xcodeproj` |

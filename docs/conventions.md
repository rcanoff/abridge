# ABridge — Development Conventions

Coding standards for this project: naming, libraries, formatting, error handling, concurrency, and testing.

For product scope, see `docs/prd.md`. For architecture and bootstrap steps, see `docs/architecture-bootstrap-guide.md`.

---

## Toolchain

| Tool | Version / setting |
|------|-------------------|
| macOS deployment target | 26.0+ |
| Xcode | 26+ |
| Swift | 6.0+ (`project.yml` sets `SWIFT_VERSION: "6.0"`), strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`) |
| Rust edition | 2024 |
| Rust MSRV | 1.89 |
| Task runner | `just` |
| Project generation | `xcodegen` (`project.yml`) |

Rust targets: `aarch64-apple-darwin` (arm64 only).

---

## Approved libraries

Pin these versions unless a PR explicitly upgrades them.

### Rust (`abridge_core`)

| Crate | Version | Purpose |
|-------|---------|---------|
| `uniffi` | 0.31 | Swift ↔ Rust FFI (proc-macro mode only; no UDL) |
| `thiserror` | 2 | Typed error enums |
| `serde` | 1 | Serialization |
| `serde_json` | 1 | JSON encode/decode |
| `tokio` | 1 | Async runtime (`rt-multi-thread`, `macros`, `sync`, `net`) |
| `axum` | 0.8 | HTTP server |
| `http` | 1 | HTTP types |
| `tracing` | 0.1 | Structured logging |
| `tracing-subscriber` | 0.3 | Log filtering (`env-filter`) |
| `rusqlite` | 0.40 | Read the Notes SQLite store (`bundled`; no system lib in the Xcode link) |
| `flate2` | 1.1 | Gzip and zlib inflation for note bodies and tables (pure-Rust backend) |
| `prost` | 0.14 | Hand-written protobuf messages for note text and embedded tables (no protoc) |
| `base64` | 0.23 | Encode/decode attachment and contact-photo bytes for MCP content items |
| `nucleo-matcher` | 0.3 | Word-level fuzzy query syntax (case-insensitive, accent-insensitive) |
| `jiff` | 0.2 | Civil time, RFC 3339, and the system time zone database (POSIX rules after the last TZif transition) |
| `anydoc` | 0.2 | Document files to Markdown (PDF, Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV; pure Rust, no network) |
| `lopdf` | 0.45.0 | Recover literal word spacing for letter-spaced PDF Markdown (same version used by `anydoc`) |
| `pulldown-cmark` | 0.13.4 | Markdown parser for Notes create/update bodies (default features off) |

Release profile: `lto = true`, `codegen-units = 1`, `opt-level = "z"`, `strip = true`.

Do not add alternative HTTP or MCP transport crates without an architecture change. MCP is served over the embedded axum server defined in the architecture guide.

### Swift

| Framework | Purpose |
|-----------|---------|
| SwiftUI | UI |
| Observation (`@Observable`) | UI state |
| Swift Testing (`import Testing`) | Unit tests |
| Security | Keychain |
| Foundation | Core types |
| Apple frameworks | Provider adapters only (EventKit, MapKit, etc.) |
| Sparkle 2.10.0 (SPM, exact pin) | App updates: `SparkleUpdaterService` owns the updater; feed and EdDSA public key live in `ABridge/Info.plist` |

No other third-party Swift dependencies unless a PR justifies them.

---

## Naming

### Rust

| Item | Convention | Example |
|------|------------|---------|
| Crate | `snake_case` | `abridge_core` |
| Module files | `snake_case.rs` | `providers.rs`, `error.rs` |
| Types (structs, enums, traits) | `PascalCase` | `ServerConfig`, `CoreError`, `ProviderBridge` |
| Functions | `snake_case` | `create_server`, `init_logging` |
| Constants | `SCREAMING_SNAKE_CASE` | — |
| JSON / config fields | `snake_case` | `payload_json`, `bearer_token` |

Keep modules focused; split when a file grows past ~150 lines.

### Swift

| Item | Convention | Example |
|------|------------|---------|
| Types | `PascalCase` | `AppStore`, `ServerService` |
| Properties and methods | `camelCase` | `permissionStatus`, `refreshStatus()` |
| Protocol seams (testability) | `PascalCase` + role suffix | `RemindersPermissionChecking`, `URLOpening` |
| Platform wrappers | `PascalCase` + `Service` | `RemindersPermissionService`, `KeychainService` |
| Provider types | `PascalCase` + `Provider` | `EventKitProvider` |
| Generated UniFFI bindings | Follow generated names | `payloadJson` (camelCase from UniFFI) |

Do not rename generated binding symbols. Wrap them in hand-written `Services/` types instead.

### Providers and operations

Rust routes by `provider` + `operation` string pairs. Framework-backed providers dispatch on the same values in Swift. Providers for Apple apps without a public framework may dispatch entirely in Rust, bypassing `ProviderBridge`; Notes is the only such provider.

| Item | Convention | Example |
|------|------------|---------|
| Provider ID | lowercase Apple framework name, or app name when no public framework exists | `"eventkit"`, `"mapkit"`, `"corelocation"`, `"notes"` |
| Operation | `snake_case` | `"list_calendars"`, `"create_event"`, `"request_access"` |
| Error codes (JSON) | `snake_case` | `"unknown_provider"`, `"unknown_operation"` |
| MCP tool name | `<provider>_<domain>_<operation>`, or `<provider>_<operation>` without a domain; rules in `AGENTS.md` § MCP tool names | `eventkit_reminders_list_lists`, `corelocation_get_current_location` |

The `provider` / `operation` pair is the internal dispatch contract, and each MCP tool name is built from it, so the external surface adds no second vocabulary. Use the same prefix for capabilities: `notes_list_notes` belongs to `notes.read`.
A tool that searches more than one framework uses provider `abridge` (`abridge_search_items`). It has no capability of its own: it is listed when any of `notes.search`, `eventkit.reminders.search`, or `eventkit.events.search` is enabled, and it searches only those stores.

Config field validation rules (host, port, provider names, bearer token): see `docs/architecture-bootstrap-guide.md` §5 validation matrix.

### Files and generated output

| Path | Edit? |
|------|-------|
| `rust/abridge_core/src/` | Yes — source of truth |
| `ABridgeCore/` | Never — regenerated by `just build-rust` (PR 2+) |
| `ABridge/Services/abridge_core.swift` | Never — copied from build output |
| `ABridge/Services/*Service.swift` | Yes — hand-written wrappers |
| `ABridge/Providers/` | Yes — thin Apple adapters |

---

## Formatting and lint

### Rust

Requires `rust/Cargo.toml` (PR 2+). Until the workspace lands, skip this section.

`rust/rustfmt.toml`:

```toml
max_width = 120
tab_spaces = 2
```

Run before commit (PR 2+):

```sh
just lint-rust    # cargo clippy -- -D warnings
just test-rust    # TZ=UTC cargo test
```

### Swift

- Config: `.swiftformat`, `.swiftlint.yml` at repo root
- Exclude generated: `ABridge/Services/abridge_core.swift`, `ABridgeCore/`
- Enable strict concurrency in `project.yml`.
- Run before commit:

```sh
just fmt-check-swift
just lint-swift
just test-swift
```

---

## CI

| Workflow | Runner | Path filter |
|----------|--------|-------------|
| Rust CI | `ubuntu-latest` | `rust/**` |
| macOS CI | `macos-26` | `ABridge/**`, `ABridgeTests/**`, `project.yml`, `rust/**` |
| Release | `macos-26` | `vX.Y.Z` tags; runs `just release-build` (see README § Releasing) |

Local parity: `just ci`. Pre-push runs a fast subset (skips `build-rust`); install via `git config core.hooksPath .githooks`.

---

## UniFFI rules

- Proc-macro mode only. No UDL files.
- Re-export the public FFI surface from `lib.rs`.
- Use `#[derive(uniffi::Record)]` for structs passed by value.
- Use `#[derive(uniffi::Enum)]` for simple enums.
- Use `#[derive(uniffi::Error)]` + `thiserror` for FFI-exposed errors.
- Use `#[derive(uniffi::Object)]` for stateful handles (`ServerHandle`).
- Use `#[uniffi::export(callback_interface)]` for Swift-implemented traits (`ProviderBridge`).
- Never `unwrap()` or `expect()` on paths reachable from UniFFI. Panics abort the app.

Changing the FFI API (PR 2+, requires `rust/Cargo.toml`):

1. Edit Rust types in `abridge_core`
2. `just lint-rust && just test-rust`
3. `just build-rust`
4. Fix Swift call sites in hand-written services
5. Never patch `abridge_core.swift` manually

---

## Error handling

### Rust

When using the **rust-best-practices** skill, these project rules override it:

- **`thiserror` only** — no `anyhow` (library crate behind UniFFI, not a CLI binary).
- No `cargo-insta` or snapshot tests; use the seams in § Testing: `MockProviderBridge` for bridge-backed calls and fixture stores/files for Notes.
- No workspace-wide `#![deny(missing_docs)]`.
- Type state pattern is optional; prefer the architecture guide's `ServerHandle` lifecycle.

- Return `Result<T, CoreError>` on all user-input and external-data paths. Rust-native providers for Apple apps without a public framework may instead return provider-local typed errors inside Rust (`NotesError`), without UniFFI error exports.
- Classify errors precisely; avoid generic catch-all buckets when a specific variant exists.
- Validate config, auth, provider names, and operations in Rust — not in Swift providers.
- Log auth failures and server lifecycle events; never log bearer tokens.

### Swift

- Translate generated `CoreError` into app-level errors in one place (e.g. `AppError` or the relevant store).
- User-visible errors: human-readable string, red styling, `.textSelection(.enabled)`.
- Never crash on permission, Keychain, or server startup paths.
- Never silently swallow errors.

### Provider errors

Bridge-backed providers return structured JSON via `ProviderResponse`:

```json
{ "code": "unknown_operation" }
```

Set `ok: false` and populate `error_json`. Do not panic or return unstructured strings.

Rust-native providers for Apple apps without a public framework report errors directly to the Rust MCP layer. Notes returns structured error JSON in one text item with `isError: true`, without `ProviderResponse`.

---

## Concurrency

### Swift

- UI stores: `@Observable` + `@MainActor`.
- Inject dependencies via protocols for testability.
- Wrap blocking UniFFI calls with `@concurrent` when they must not run on the main actor.
- Avoid `Task.detached` unless there is a concrete isolation reason.

### Rust

- The embedded server owns its Tokio runtime explicitly.
- `start()` fails cleanly if the port cannot be bound.
- `stop()` performs graceful shutdown with explicit signaling.
- Prefer stop-and-recreate over hot-mutating a live server handle.

---

## Logging

- Rust: `tracing` only. Export `init_logging()`; call once from Swift at startup.
- Disable ANSI color in FFI/logging contexts.
- Swift: no custom logging framework in v1; surface operational state through UI and Rust diagnostics.

---

## Testing

### Commands

```sh
just test-swift    # available now
just test-all      # test-swift; includes test-rust when rust/Cargo.toml exists
```

PR 2+ (requires `rust/Cargo.toml`):

```sh
just test-rust     # TZ=UTC cargo test
just lint-rust     # clippy -D warnings
just build-rust    # XCFramework + bindings
```

Always set `TZ=UTC` for deterministic timestamp assertions.

### Rust

- Unit tests: `#[cfg(test)]` modules in source files.
- Integration tests: `rust/abridge_core/tests/`.
- Use `MockProviderBridge` as the primary seam for server, routing, and auth tests that dispatch through `ProviderBridge`.
- Test `agent_shape` with serialized framework fixtures: summary/detail consistency, omission of internals and empty values, meaningful false outcomes, and photos outside JSON. Exercise `prepare` request rewrites and the shaped MCP response through `MockProviderBridge`.
- Test shared `fuzzy` query syntax, word boundaries, case-insensitivity, accents, weighted ranking, per-line matching, pagination, and marked excerpts. Notes fixtures also cover Markdown, list filtering, search-cache invalidation, attachment content, and write-confirmation outcomes.
- Rust-native providers for Apple apps without a public framework use their own data-access seam. Notes uses SQLite fixture stores and fixture attachment files in temporary directories, built by `fixture.rs` and `attachment_fixture.rs` under `rust/abridge_core/src/notes/`, not `MockProviderBridge`. `notes_get_attachment` Vision tests mock `ProviderBridge` for that call only. Never access the real Notes store or run `osascript` in tests. Do not run `sips` except in the macOS-only rendition test with a fixture image.
- Test config validation, auth enforcement, provider dispatch, and lifecycle without real Apple APIs.

### Swift

- Framework: Swift Testing (`@Suite`, `@Test`, `#expect`).
- Mock platform dependencies via protocols (`RemindersPermissionChecking`, etc.).
- Test stores, mappers, and error translation — not live EventKit permission dialogs.
- Live Apple framework and permission-dialog tests are manual smoke tests only.
- Debug builds and the test host use the bundle identifier `io.github.rcanoff.ABridge.debug` (shown as "ABridge Debug"), so their privacy grants (Full Disk Access, Automation, Calendars) are separate from the installed app's and a test run never invalidates them. Grant the Debug app its own permissions when testing live features.

### What not to automate in CI

- EventKit permission prompts
- Keychain access requiring user interaction
- End-to-end MCP client sessions (manual smoke until a harness exists)

---

## Auth conventions

- Header format: `Authorization: Bearer <token>`
- Missing or malformed auth: reject with an HTTP auth error (do not fall through to handlers).
- Invalid token: reject; do not log the token value.
- Token storage: Swift Keychain only. The Keychain service name is `<bundle identifier>.mcp-bearer-token`, so Release stays `io.github.rcanoff.ABridge.mcp-bearer-token` and Debug (`io.github.rcanoff.ABridge.debug`) uses `io.github.rcanoff.ABridge.debug.mcp-bearer-token`. Rust receives the token at runtime via `ServerConfig`.
- V1 API key format: `ab_live_` + 43-character unpadded base64url segment (32-byte CSPRNG). Legacy Keychain tokens without the prefix are preserved on load; rotation issues a new `ab_live_` key.

---

## JSON and payloads

- Framework-backed provider request/response bodies cross UniFFI as JSON strings (`payload_json`, `error_json`). Swift calls the framework and serializes its objects; Rust shapes the client response.
- Notes runs directly in Rust without a Swift callback. Diagnostics is also shaped in Rust.
- Validate payload size in Rust before parsing.
- Return JSON in an MCP text item. Files and photos follow as separate MCP content items, never base64 fields inside that JSON.

### Agent-shaped responses

Carry what an agent reads, links, and acts on: content, actionable identifiers, and enough context for the next call. Leave out framework/store internals, sync bookkeeping, UI state, internal UUIDs, invalid sentinels such as `-1`, and raw binary. Derived names, folder paths, counts, snippets, and match evidence are useful response fields, not parallel business logic.

Omit fields whose values are null, false, empty strings, or empty containers. An absent key means null, false, or empty; say this in tool descriptions. Keep false explicitly when it communicates an outcome: diagnostics retains `success` and `logging_enabled`. Preserve meaningful numeric zero values rather than treating every zero as empty.

Use `snake_case` keys, ISO 8601 timestamps, and string URLs. Keep identifiers usable as inputs to related tools. Write arguments map to the underlying Apple API or scripting interface. Event start and end, including each list or search occurrence, are local wall time with a numeric offset in the event time zone, or the server Mac's time zone when the event has none (not the caller's), plus `time_zone` when known. Pass an absolute time such as `2026-10-26T09:00:00-04:00`, or wall time `2026-10-26T09:00:00` with `time_zone` `America/New_York`. All-day events return `start_date` and `end_date` as calendar dates `YYYY-MM-DD`. `end_date` is exclusive (the day after the last day). Each calendar day is that serialized instant converted into the event's time zone, or this Mac's time zone when the event has none. An all-day write is `YYYY-MM-DD`. The server does not treat its clock or time zone as the caller's. Reminder due and start dates in responses are `YYYY-MM-DD` when date-only. A time whose components include `time_zone` is local wall time with that zone's offset. A time with no components `time_zone` is floating wall time with no offset and `floating: true` (that clock time wherever the person is, not the server's zone). The components' `time_zone` stamps a zoned time. The reminder `time_zone` does not. A due time written without a components `time_zone` stays floating. A title search for events with no dates covers 1 year before through 2 years after the server Mac's current time (EventKit returns at most a four-year span). Contact birthdays and reminder write inputs stay date-component objects. Contact labels are plain words (`mobile`, `home fax`); a label that is not an Apple token is unchanged. Contact phone, email, and URL values are strings with an optional label on read and write. Postal addresses use the same object on read and write. Omitting `container_identifier` on `contacts_create_contact` and `contacts_create_group` uses the default container. `contacts_list_containers` lists each container's identifier, name, and type, and `is_default` on that default. Contact list and search summaries include `identifier`, `name`, `nickname`, `organization_name`, `job_title`, `container_identifier`, the first phone, and the first email, without labels or photo bytes. On `contacts_update_contact`, omitted fields stay unchanged and each multi-value list replaces the whole list; get the contact first to change one email or phone. Labels are words (`mobile`, `home`, `work`, `home fax`). Event notes are plain text or Markdown. Event detail keeps `event_identifier`. Occurrences of a series share `event_identifier`; each row's `start_date` is that occurrence. Pass it as `occurrence_date` to get, update, or delete that occurrence. A recurring update or delete without `occurrence_date` returns `occurrence_required` and changes nothing. `span` is `this_event` (default) or `future_events`. `eventkit_reminders_delete_reminder` takes `calendar_item_identifier` or `reminder_title` (exact, case-insensitive); `calendar_identifier` limits a title to one list. Several matches return `reminder_title_ambiguous` and delete nothing. `eventkit_events_delete_event` takes `event_identifier` or `event_title` the same way, in the title-search window unless `start_date` and `end_date` are set. Occurrences of one series count as one event. Several events return `event_title_ambiguous`. Recurrence `days_of_the_week[].day_of_the_week` is `sunday` through `saturday`. `week_number` stays an integer. Calendar and reminder-list `source` is `{source_identifier, title, type}`.

### Summary and detail

- List/search tools return compact summaries with enough information to pick an item and call get/update.
- `get_*` and writes that return an object use its detail shape, including the content needed to read and act on it.
- Reuse one summary and one detail shape per type across tools. Types with little metadata may share both shapes. Search adds `score` and `matches` evidence; Notes search uses matched excerpts instead of the list snippet.

Shaping lives in `rust/abridge_core/src/agent_shape/`: `mod.rs` selects the shape and prepares requests; `eventkit.rs`, `contacts.rs`, `mapkit.rs`, `location.rs`, and `vision.rs` shape provider data; `rank.rs` uses shared fuzzy search; `util.rs` handles common omission and encoding. `mcp/mod.rs` applies shaping after the Swift callback and before returning content. Diagnostics uses `shape_usage_log` in the same module. `prepare` may rewrite a request: a contacts fuzzy query fetches `list_contacts` for the selected container, then ranks in Rust.

`eventkit_events_list_events`, `eventkit_reminders_list_reminders`, `contacts_list_contacts`, and `contacts_list_groups` default to 50 items (maximum 200). `offset` pages the shaped list. `prepare` strips `limit` and `offset` before the provider call.

Notes uses `rust/abridge_core/src/notes/shape.rs` directly. Its `project.rs` store projection is internal to write confirmation, not an MCP response. `notes_list_folders` returns folders with `account {identifier, name}`, so account discovery needs no separate tool. Folders Notes has not downloaded from iCloud yet are left out. Notes list/search summaries omit the body; `notes_get_note` and note writes return the detail shape with Markdown `body` and attachment cards in body order. Gallery pages are nested on the gallery as `pages`. `attachment_count` counts top-level body references, and a gallery counts once. Saved text is one copy in `text`. Tab-separated fragments are collapsed, then each line is keyed as lowercase letters and digits, and a later line is dropped when its key equals an earlier kept key, or is contained in one and the shorter key is at least 4 characters and at least 80% of the longer key's length. When a later key contains an earlier kept key under that same test, the later line replaces the earlier one in place. A line with no letters or digits is kept and is not a match. `description` is the image classification when its keyed text is not the saved text. Note detail caps `text` at 1,500 characters (`text_truncated` when cut, `text_source` `saved`). `page_count` is set for a scan or pdf when the page tree records it, and omitted rather than guessed. `body_update` is `{status: blocked, reason, message}` when a body replacement would be refused. File names are `attachments` when files block the edit. It is omitted when an update is allowed. `notes_get_attachment` defaults to Markdown in `content` (saved text when Notes has it, for a scan, image-only PDF, photo, or drawing; paged with `max_characters` and a Unicode-character `offset`). Every markdown response names `text_source`. `format` `image` and `original` omit saved text. `source_path` is the Notes file. `file_size` is the size of the file on disk when that file is present, and the size Notes stored otherwise. `notes_get_note` uses the same rule. `format` `original` copies it to `$TMPDIR/abridge-attachments/<attachment identifier>/<file name>` with no size cap and no blob, and sets `file_path` to that copy. Search still indexes the stored text. A missing, locked, or not-yet-downloaded body is omitted.

Notes renders one file link per attachment identifier, even when Notes stores repeated placeholders. Inline tables are already in `body`; they are omitted from `attachments` and `attachment_count`, so no extra attachment fetch is needed.

`notes_list_notes` and `notes_search_notes` take `folder_identifier` or `folder_path` (the path `notes_list_folders` returns; case-insensitive exact match), exactly one when a folder is set. `account_identifier` selects the account when that path exists in more than one. Without either, lists and searches exclude Recently Deleted, notes without a folder, notes awaiting download, and notes marked for deletion. An explicit folder scopes the results to that folder, including Recently Deleted. `notes_get_note`, `notes_update_note`, `notes_move_note`, and `notes_delete_note` take `note_identifier` or `note_title` (exact, case-insensitive). A title matches live notes only, and notes in Recently Deleted only when the folder is that folder. On `notes_move_note`, `folder_path` and `folder_identifier` are the destination, and `note_title` finds the source. No match is `not_found`. Several matches are `note_title_ambiguous` and list up to 10 candidates (identifier, folder path, modification date). A missing or ambiguous `folder_path` lists candidate paths with identifiers. Lists order pinned notes first, then most recently modified.

### Text as Markdown

Return rich text bodies as Markdown. `notes/markdown.rs` renders Notes headings, `- [ ]` and `- [x]` checklists, numbered/bulleted lists, bold, italic, strikethrough, links, fenced code, and tables. Files and galleries use `[title](attachment:<id>)`; inline hashtags, mentions, and Math results remain text. Attachment cards carry `kind`, saved `text`, `handwriting`, and `description`.

Notes create/update `body` is that same Markdown. `notes/markdown_html.rs` turns it into the HTML Notes' scripting interface keeps. A leading `# Title` is the title line. `#` and `##` are stored as bold 24pt and 18pt text with no paragraph style and read back as `#` and `##`. Headings beyond `##` read back as bold. Each blank line between top-level blocks becomes one empty Notes line (`<div><br></div>`), because Notes has no paragraph spacing; leading blank lines and the separators the converter inserts to end a list are not written. Reading a note maps each empty line back to a blank line, so read, edit, and write round-trips the spacing. Notes swallows the first empty line after a table, so a blank line after a table is written as two empty lines. Notes may normalize links: a bare domain gains a trailing slash. Creating `- [ ]` / `- [x]` stores ordinary bullets, not a native checklist, so a later update can replace that text. `notes_update_note` replaces the whole body. Block quotes become plain paragraphs. Fenced code round-trips; inline code reads back as plain text. Tables and a `---` divider round-trip. HTML in the body is converted. The returned note includes warnings naming every converted HTML tag and every removed HTML tag, and headings are stored as bold text and read back as `#` / `##` headings. `[title](attachment:<id>)` does not attach or keep a file. `notes_update_note` returns `body_would_drop_content` when the note is password protected or has a checklist or an attachment other than a table, and the message names each one. It returns `body_unavailable` when the current body is missing, not downloaded, past the inflate limit, or not a note protobuf, including a direct identifier that is still awaiting download. Nothing was changed. The script then refuses with `note_changed` when the live note's modification date is newer than that snapshot or the live attachment count differs. Confirmation waits until `note_data` changes, not the modification date alone. A body that already matches the stored note after Markdown normalization succeeds without waiting. `write_unconfirmed`, including an osascript timeout, means the change may have happened; check before retrying. Notes with files or checklists cannot have their text edited through scripting without losing them, and nothing was changed. `notes_delete_note` adds `deletion` `recently_deleted`. `notes_delete_folder` rechecks the live folder and returns `folder_not_empty` when it holds notes or subfolders. `notes_delete_folder` asks Notes to save the delete, then polls until the row is gone or marked for deletion. If Notes already dropped the folder from scripting (`-1728`), the same save runs. A row that is still listed is `folder_delete_unsaved`.

Tables immediately following a paragraph or list need no blank line: the parser normalizes that separation before converting the body to Notes HTML. An update that replaces an existing table with text returns a warning.

Vision's Swift serializer bounds cyclic document graphs: it writes a node once per path and stops when the same region and text repeat above it. See `VisionDocumentNodeKey`. `agent_shape::vision_text` and `agent_shape::vision_markdown` assemble that JSON into reading-order text and Markdown. `vision_recognize_text` returns `text`. `vision_recognize_documents` returns `markdown`, plus `detected` when Vision finds dates, phone numbers, links, or barcodes. Per-line boxes and the document structure are included only when `include_geometry` is true. A PDF page is rasterized at twice its point size, or smaller when that would pass 40 million pixels. `vision_recognize_text` splits an image whose height is more than 1.5 times its width into overlapping tiles and returns one observation list in whole-image coordinates. A wide image is not tiled. `vision_recognize_documents` uses that render and is not tiled.

### Fuzzy text search

Use shared `crate::fuzzy` in `rust/abridge_core/src/fuzzy.rs`, backed by `nucleo-matcher`, for local text corpora:

- Space-separated terms must all match; a term may match any field or any line of a long-text field.
- A fuzzy term matches inside one word (a run of letters or digits; a hyphen or apostrophe stays inside the word), so a typo or subsequence cannot jump across words. `^term` is a word prefix and `term$` is a word suffix, including either side of a hyphen or apostrophe.
- `"buy milk"` is one exact phrase (spaces stay; case and accents are ignored). A stray unmatched `"` is stripped. `'exact` is a substring of one word and does not quote spaces (`'pão de queijo'` stays separate terms). `!negate` excludes a match, and `a | b` accepts either alternative. Matching is case-insensitive and accent-insensitive (`acao` matches `ação`).
- Weight fields, match long text per line, and return best-first hits with `score` and `matches: [{field, excerpt}]`. Excerpts mark matched characters with `«»`; omit `matches` when there is no positive match excerpt.

`notes_search_notes` and contacts/events/reminders search `query` use this engine. Apple predicates still perform date, calendar, and completion filtering. Contacts' `name`, `email_address`, and `phone_number` predicates apply when `query` is absent; `container_identifier` applies on either path. MapKit uses its own natural-language query, not fuzzy search. A landmark is resolved with `mapkit_search_places` and a region bias (`region` plus `region_priority` `required`); `mapkit_forward_geocode` looks up a street address. A MapKit `region` needs only `center`: Rust fills an omitted or 0 `span` delta with 0.1°, and an omitted or 0 `mapkit_search_nearby` `radius_meters` with 1000, before Swift. `radius_meters` is a radius: Swift's region is twice it across. `mapkit_search_nearby` takes exactly one of `coordinate` or `region`. Every place summary carries `maps_url`, an Apple Maps place link (`place-id` when MapKit has an identifier, else `coordinate` with the name). Some MapKit places have no identifier, and a name search returns them without one too. `mapkit_estimate_travel_time` and `mapkit_calculate_route` take a coordinate or a MapKit `identifier` on each endpoint, and at most one of `departure_date` or `arrival_date`. `name` is a label and does not geocode. A coordinate alone is reverse-geocoded for a name, or the name is omitted instead of `Unknown Location`. Arrival and departure are local wall times with a numeric offset in the endpoint's time zone, or the server Mac's time zone when the place has none (not the caller's). Omitting departure and arrival uses the server Mac's current time. `waypoints` (at most 8) on those two tools are routed in Rust (`mcp/trip.rs`), one Swift call per leg, because MapKit routes one source to one destination: a route leg uses its first route, a departure time (this Mac's current time when neither date is given) moves forward by each leg's travel time, and an arrival time is routed from the last leg backward. A route with waypoints is one route with `legs`; a travel time adds the legs and lists them in `legs`. Every route and travel-time response carries `maps_url`, an Apple Maps unified directions URL with the stop coordinates, `source-place-id`, `waypoint-place-id`, and `destination-place-id` for stops whose identifier MapKit returned (a caller's identifier that failed to resolve is not echoed), `mode` (omitted for `any`), and `avoid` from the toll and highway preferences. Maps prefers a Place ID over the coordinate, pairs `waypoint-place-id` with waypoints by position, and ignores them when the counts differ, so once any waypoint has an identifier each waypoint gets one (empty when it has none). `mapkit_open_navigation` builds that URL in Rust (looking up an identifier-only stop with `get_place` for its coordinate), and Swift opens it in Maps on this Mac; the response returns it as `maps_url`. MapKit cannot avoid one named road, and a route's steps can skip roads it stays on. A MapKit place search with no region is biased near this server Mac, not near the caller. `corelocation_get_current_location` is this server Mac's location, not the caller's. Its failures are `location_services_off`, `permission_denied` (denied, restricted, or not determined), or `location_unknown` (no fix or timeout, including kCLErrorDomain error 0, locationUnknown); the message says what to change. Vision tools take exactly one of `image_data` (base64) or `image_path` (an absolute path of a regular file on this Mac, at most 20 MiB; a symlink is followed when the final target is a regular file). A PDF is accepted by its contents, not its file extension. `page` selects one page (default 1). A PDF result includes `page` and `page_count`. A page past the end is `page_out_of_range`. `page` greater than 1 on an image is `invalid_arguments`. An encrypted or unreadable PDF is an error. `vision_recognize_text` returns `text` in reading order. A PDF page is rasterized at twice its point size, capped at 40 million pixels. An image taller than 1.5:1 is tiled for text recognition only; a wide image is not. Boxes stay in whole-image coordinates. `vision_recognize_documents` returns `markdown` and is not tiled. Boxes and the document structure are included only when `include_geometry` is true. Text recognition turns language detection and language correction on unless the call passes the language fields. Core Location and Vision have no fuzzy query.

`abridge_search_items` uses the same engine across notes, reminders, and events, then merges by score. It searches only the enabled stores. A failing store is reported in `store_errors` and does not drop the others. Its event date window is the `eventkit_events_search_events` window. An event item's `start_date` is the `occurrence_date` to pass to get, update, and delete, shaped like other event times: local wall time with a numeric offset in the event's time zone, or this Mac's when the event has none; all-day `YYYY-MM-DD` with `is_all_day`. `limit` defaults to 20 (maximum 100). `offset` skips that many merged hits (default 0). Each store is read through its top `offset + limit` candidates so the next page continues that ranking.

Notes caches an in-memory text index until `NoteStore.sqlite` or `NoteStore.sqlite-wal` changes size or modification time. A build publishes only when that stamp is unchanged from before the snapshot was loaded, and an older build does not replace a newer entry. Notes search defaults to 20 hits (maximum 100); contacts/events/reminders fuzzy queries default to 50 (maximum 200). `offset` pages the ranked results.

Notes indexes locally available document text as well as text Notes has saved. Search excerpts are the matched line plus up to two surrounding lines, capped at 600 characters, with the match inside `«»`. One match per attachment and per body field; terms on different lines are joined inside that cap. A match on attachment text includes `attachment_identifier`, `attachment_title`, and `kind`, plus `page_count` for a scan or pdf when the count is known. Each hit includes `attachments` (`identifier`, `title`, `kind`, `page_count` when known) in body order, top-level only, omitted when the note has none. PDF extraction repairs letter-spaced lines from the PDF's encoded text strings only when their non-whitespace text agrees exactly. Search or list returns note identifiers. `notes_get_note` returns the body. When a search match names an attachment, call `notes_get_attachment` directly.

### Binary content and renditions

Shared image formats, size limits, and JPEG rendering live in `rust/abridge_core/src/rendition.rs`.

- Return JPEG/PNG/GIF/WebP as MCP `image` content when its base64 is at most 5 MB (5 × 1024 × 1024 bytes). Other files use embedded `resource` content with a base64 `blob`.
- For incompatible image formats or images over that base64 limit, use `/usr/bin/sips` with a timeout to re-encode to JPEG at quality 80. Try long edges of 2048, 1568, 1024, then 768 pixels until the image fits. `sips` writes into a new private directory (mode 0700, unpredictable name) that is removed when the rendition finishes.
- A successful rendition replaces the original bytes and does not use the 20 MiB raw-file cap. The JSON sets `rendition` to `jpeg` for a scaled photo and `jpeg_page` for a rendered PDF page. A PDF page other than the first is copied into a one-page PDF with `lopdf` before `sips` renders it, and the JSON carries `page` and `page_count`. If no rendition fits, return the original image as an embedded resource within that cap. `notes_get_attachment` with `format` `original` does not inline the file: it copies it to `$TMPDIR/abridge-attachments/<attachment identifier>/<file name>` (directory 0700, file 0600, entries older than 24 hours removed). The export root is rejected when it is a symlink or not a directory, and cleanup and the copy do not follow symlinks. The call returns `file_path` for that copy. There is no size cap and no blob.
- Contact photos follow the JSON of get/write results as content items; list/search never carry image bytes. If a photo cannot be rendered and exceeds the resource cap, omit the photo content while returning the contact detail.
- `notes_get_attachment` reads `Accounts/<account>/Media/...`, `Accounts/<account>/FallbackPDFs/...`, or `Accounts/<account>/FallbackImages/...` beside the store. `format` defaults to `markdown`: JSON only, with `content` set to Markdown and `format` set to `markdown`. `content` is paged with `max_characters` (default 15000, at most 100000) and `offset` (a Unicode-character offset); a cut page sets `content_truncated` and `next_offset`. `source_path` is the absolute Media, FallbackPDF, or FallbackImage path when the file is on disk. `file_size` is the size of the file on disk when that file is present, and the size Notes stored otherwise. `notes_get_note` uses the same rule. The MIME type comes from the file header (JPEG, PNG, GIF, WebP, HEIF/HEIC, PDF, TIFF, QuickTime/MP4), with the extension only as a fallback. Markdown and image do not copy it. Documents (PDF, Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV) are converted with `anydoc`. A file larger than 50 MiB is not read (`extraction_too_large`, no text), including for search indexing. Unsupported video, audio, and other non-document types are recognized from the UTI, extension, and a short header and are not read in full. A text PDF stays an `anydoc` conversion (`text_source` `document`). Saved text is instant and is the default for a scan, an image-only PDF (`anydoc` `NeedsOcr`), a Paper scan (`com.apple.paper.doc.scan`, `com.apple.paper.doc.pdf`), a photo, or a drawing when Notes has it; it may be partial or garbled on tall scans. When nothing is saved and Vision is enabled, Vision runs. `text_source` `saved` never runs Vision. `text_source` `vision` reads each page fresh (slower; the first call can take up to a minute while macOS loads text recognition) and does not fall back to saved text (`vision_unavailable` when Vision is disabled, `vision_failed` when Vision returns nothing): a scan or image-only PDF sends each page as a one-page PDF, and a photo or drawing sends the original file when it is at most 20 MiB, otherwise a JPEG rendition. More than one page comes back as `## Page N` sections. At most 20 pages are read per call; `pages_truncated` and `next_page` say when pages remain. Every markdown response names `text_source` (`saved`, `vision`, `document`, `table`, or `gallery`), plus `kind` and `page_count` for a scan or pdf when known. `page` on markdown reads that one page with Vision; `text_source` `saved` together with `page` is `invalid_arguments`, as is `text_source` on `format` `image` or `original`. `page` is checked like `format` `image`. `notes_get_note` keeps the saved text on each card. Photos and drawings with no saved text say the image is available with `format` `image`. A gallery lists its pages (`text_source` `gallery`); a table is its Markdown (`text_source` `table`). `format` `image` returns a viewable JPEG (photo/drawing rendition, or page 1 of a PDF or scan) and omits saved text. `format` `original` returns JSON only: `file_path` is the temp copy and `source_path` is the Notes file. Missing downloads, locked files, encrypted documents, and attachments with nothing to read return typed errors.

---

## Commit and PR hygiene

- Small, focused PRs with reviewable diffs.
- Run `just test-swift` or `just test-all` before opening a PR. Use rust recipes only when `rust/Cargo.toml` exists.
- Do not commit generated artifacts that are reproducible from `just build-rust` (PR 2+) unless the repo already tracks them by policy.
- Tracked docs: `docs/conventions.md`, `docs/prd.md`, `docs/architecture-bootstrap-guide.md`. Other paths under `docs/` (plans, specs, reviews) stay local via `.gitignore`.
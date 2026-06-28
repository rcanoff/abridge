# PR 2c: Swift Integration + Manual Start UI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire UniFFI Rust core into the menu bar app so the user can manually start/stop the local HTTP server and see status in the popover.

**Architecture:** `just build-rust` produces `AppleBridgeCore/apple_bridge_core.xcframework` and copies generated `apple_bridge_core.swift` into `AppleBridge/Services/`. Hand-written `ServerService` wraps UniFFI on `@MainActor`; `ServerStore` drives popover UI with a protocol seam for tests. Stub `AppleProviderBridge` satisfies `ProviderBridge` until MCP tools land. No Keychain, no auth, no auto-start.

**Tech Stack:** UniFFI 0.31, Swift 6, SwiftUI, Swift Testing, xcodegen, Rust staticlib + XCFramework

**Spec:** `docs/superpowers/specs/2026-06-27-pr2-mcp-server-design.md` § PR 2c  
**Branch:** `feat/pr2c-swift-server-ui`

---

## File Map

| File | Responsibility |
|------|----------------|
| `rust/build-macos.sh` | Release build (arm64 + x86_64), lipo, UniFFI Swift gen, XCFramework |
| `project.yml` | Link `apple_bridge_core.xcframework`; strict concurrency unchanged |
| `AppleBridge/Services/apple_bridge_core.swift` | **GENERATED** — copy from build; do not hand-edit |
| `AppleBridge/Services/ServerServing.swift` | Protocol seam for `ServerStore` tests |
| `AppleBridge/Services/ServerService.swift` | `@MainActor` UniFFI wrapper; `CoreError` → user strings |
| `AppleBridge/Providers/AppleProviderBridge.swift` | Stub `ProviderBridge` → `not_implemented` |
| `AppleBridge/Models/ServerRunState.swift` | UI enum: stopped / starting / running / error |
| `AppleBridge/Models/ServerStore.swift` | `@Observable` server state + start/stop/refresh |
| `AppleBridge/Views/MenuBarPopoverView.swift` | Server section + Start/Stop buttons |
| `AppleBridge/AppleBridgeApp.swift` | Wire `ServerStore`; refresh on appear + `didBecomeActive` |
| `AppleBridgeTests/MockServerService.swift` | Test double for `ServerServing` |
| `AppleBridgeTests/ServerStoreTests.swift` | Store start/stop/status/error paths |
| `AppleBridgeTests/AppleProviderBridgeTests.swift` | Stub returns `not_implemented` |

**Generated (gitignored):** `AppleBridgeCore/` — produced by `just build-rust`

**Commit after first build:** `AppleBridge/Services/apple_bridge_core.swift` (tracked; required for `xcodebuild` without a pre-build script in CI)

---

## Prerequisites

- [ ] On `main` with PR 2b merged (`just test-rust` green)
- [ ] Rust targets installed: `rustup target add aarch64-apple-darwin x86_64-apple-darwin`
- [ ] `xcodegen` available (`which xcodegen`)

---

### Task 1: Rust → Swift build pipeline

**Files:**
- Create: `rust/build-macos.sh`
- Modify: `rust/AGENTS.md` (one line: release builds must **not** pass `--features test-sync`)

- [ ] **Step 1:** Copy `build-macos.sh` from `docs/architecture-bootstrap-guide.md` § Step 6 (unchanged script body)
- [ ] **Step 2:** `chmod +x rust/build-macos.sh`
- [ ] **Step 3:** Run `just build-rust` — expect `AppleBridgeCore/apple_bridge_core.xcframework` and copied `AppleBridge/Services/apple_bridge_core.swift`
- [ ] **Step 4:** Verify build uses plain `cargo build --release` (no `test-sync` feature)
- [ ] **Step 5:** Commit `build-macos.sh` + generated `apple_bridge_core.swift` (not `AppleBridgeCore/`)

---

### Task 2: Xcode project links XCFramework

**Files:**
- Modify: `project.yml`
- Regenerate: `AppleBridge.xcodeproj`

- [ ] **Step 1:** Add framework dependency to `AppleBridge` target:

```yaml
    dependencies:
      - framework: AppleBridgeCore/apple_bridge_core.xcframework
        embed: false
```

- [ ] **Step 2:** `xcodegen generate`
- [ ] **Step 3:** `just build-rust && xcodebuild build -project AppleBridge.xcodeproj -scheme AppleBridge -destination 'platform=macOS' -quiet` — app links without Swift service files yet (may need empty compile fix if no generated swift committed yet)

---

### Task 3: Stub `AppleProviderBridge` (TDD)

**Files:**
- Create: `AppleBridge/Providers/AppleProviderBridge.swift`
- Create: `AppleBridgeTests/AppleProviderBridgeTests.swift`

- [ ] **Step 1:** Failing test — `callProvider` returns `ok: false` and error JSON containing `not_implemented`
- [ ] **Step 2:** Implement stub conforming to generated `ProviderBridge` protocol
- [ ] **Step 3:** `just test-swift` — new test passes

---

### Task 4: `ServerServing` protocol + `ServerService`

**Files:**
- Create: `AppleBridge/Services/ServerServing.swift`
- Create: `AppleBridge/Services/ServerService.swift`
- Create: `AppleBridge/Models/ServerRunState.swift`

**`ServerServing` surface (test seam):**

```swift
@MainActor
protocol ServerServing: AnyObject {
    func refreshStatus() -> ServerRunState
    func start(host: String, port: UInt16) throws
    func stop() throws
}
```

**`ServerService` rules:**
- Call `initLogging()` once before first `createServer`
- Default config per spec: host `127.0.0.1`, port `3020`, providers `[eventkit enabled]`
- Hold `ServerHandle?`; recreate on host/port change (stop + nil + create)
- Map every `CoreError` variant to a stable user-visible string in one private helper
- `refreshStatus()` reads `serverStatus(handle)` → map `running` + `last_error` to `ServerRunState`

- [ ] **Step 1:** Add `ServerRunState` enum + display helpers
- [ ] **Step 2:** Implement `ServerService` (no store tests yet)
- [ ] **Step 3:** Build succeeds with generated UniFFI types

---

### Task 5: `ServerStore` + unit tests (TDD)

**Files:**
- Create: `AppleBridge/Models/ServerStore.swift`
- Create: `AppleBridgeTests/MockServerService.swift`
- Create: `AppleBridgeTests/ServerStoreTests.swift`

Mirror PR 1 `AppStore` patterns: `@Observable`, `@MainActor`, inject `any ServerServing`, `private(set)` state, `lastError` on failures.

**Store state:**
- `runState: ServerRunState` (default `.stopped`)
- `host` / `port` (defaults `127.0.0.1` / `3020`)
- `lastError: String?`
- `isStarting: Bool` (true while awaiting `start`)

**Actions:**
- `refreshStatus()` — delegate to service; clear `lastError` on success path
- `startServer()` — guard not already starting/running; set loading; call service; map errors
- `stopServer()` — call service; refresh

- [ ] **Step 1:** Failing tests: refresh maps running/stopped; start success; start failure sets `lastError`; stop clears running; double-start guarded
- [ ] **Step 2:** Implement `ServerStore`
- [ ] **Step 3:** `just test-swift` — all ServerStore tests pass

---

### Task 6: Popover UI

**Files:**
- Modify: `AppleBridge/Views/MenuBarPopoverView.swift`

Add server section below reminders (keep `AppStore` and `ServerStore` separate):

| `ServerRunState` | UI |
|------------------|-----|
| stopped / error | **Start Server** button |
| running | **Stop Server** button |
| starting | Disabled button + `ProgressView` |

- Show `host:port` line (`127.0.0.1:3020`)
- Server errors: `.foregroundStyle(.red)`, `.textSelection(.enabled)`
- Use `foregroundStyle()` not `foregroundColor()`

- [ ] **Step 1:** Extend view to accept `@Bindable var serverStore: ServerStore`
- [ ] **Step 2:** Wire buttons to `startServer()` / `stopServer()` via `Task { }`
- [ ] **Step 3:** Build + existing Swift tests still pass

---

### Task 7: App wiring

**Files:**
- Modify: `AppleBridge/AppleBridgeApp.swift`

- [ ] **Step 1:** `@State private var serverStore = ServerStore()`
- [ ] **Step 2:** Pass both stores to `MenuBarPopoverView`
- [ ] **Step 3:** On appear + `didBecomeActive`: `store.refreshStatus()` **and** `serverStore.refreshStatus()`
- [ ] **Step 4:** Confirm app does **not** auto-start server on launch

---

### Task 8: Verification

- [ ] `just lint-rust && just test-rust`
- [ ] `just build-rust` (fresh machine simulation: clean `AppleBridgeCore`, rebuild)
- [ ] `just test-swift`
- [ ] Manual: launch app → **Start Server** → `curl http://127.0.0.1:3020/health` → `{"ok":true}`
- [ ] Manual: **Stop Server** → curl fails
- [ ] Diff check: no Keychain, no auth middleware, no `/mcp` routes, no EventKit tool code

---

## Success Criteria (from spec)

- [ ] `just build-rust` produces XCFramework and Swift bindings
- [ ] App builds and links Rust core
- [ ] Manual start/stop works from popover
- [ ] `/health` responds while running
- [ ] Swift tests pass
- [ ] No Keychain, bearer token, or `/mcp` tools

---

## Non-goals (do not implement in this PR)

- `KeychainService`, bearer token, auth UI (PR 2d)
- `POST /mcp` or MCP tool implementations
- EventKit provider operations
- Auto-start on app launch
- Port/token persistence in settings

---

## Agent notes

**Swift skills required:** swiftui-pro, swift-testing-pro, swift-concurrency-pro before editing Swift.

**Generated code:** Never edit `apple_bridge_core.swift` or `AppleBridgeCore/` by hand.

**CI order:** `just build-rust` before `xcodebuild` (XCFramework is gitignored).

**Review triage:** Use one-table format from `AGENTS.md` when acting on review feedback.
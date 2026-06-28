# Launch at Login — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional Launch at login toggle (off by default) that registers the menu bar app via `SMAppService.mainApp`, independent of MCP server restore.

**Architecture:** `AppSettings` persists `launchAtLogin`; a `LaunchAtLoginManaging` protocol seam wraps `SMAppService`; `SettingsStore` orchestrates toggle changes and launch-time reconciliation (system status wins); `MCPSettingsView` adds a Startup section. Rust unchanged.

**Tech Stack:** Swift 6, SwiftUI, Observation (`@Observable`), Swift Testing, `ServiceManagement` (`SMAppService`), xcodegen

**Spec:** `docs/superpowers/specs/2026-06-28-launch-at-login-design.md`  
**Issue:** [#39](https://github.com/rcanoff/apple-bridge/issues/39)  
**Branch:** `feat/launch-at-login`

---

## File Map

| File | Responsibility |
|------|----------------|
| `AppleBridge/Models/AppSettings.swift` | `launchAtLogin` UserDefaults persistence |
| `AppleBridge/Services/LaunchAtLoginManaging.swift` | Protocol + `LaunchAtLoginError` |
| `AppleBridge/Services/SMAppLaunchAtLoginService.swift` | Production `SMAppService.mainApp` wrapper |
| `AppleBridge/Models/SettingsStore.swift` | Toggle orchestration + launch reconcile |
| `AppleBridge/AppleBridgeApp.swift` | Call reconcile before MCP restore |
| `AppleBridge/Views/Settings/MCPSettingsView.swift` | Startup section + toggle binding |
| `AppleBridgeTests/MockLaunchAtLoginService.swift` | Test double |
| `AppleBridgeTests/AppSettingsTests.swift` | Persistence tests |
| `AppleBridgeTests/SettingsStoreTests.swift` | Orchestration + reconcile tests |
| `project.yml` | Link `ServiceManagement.framework` |

---

## Prerequisites

- [ ] On `main`, clean working tree
- [ ] Create branch: `git checkout -b feat/launch-at-login`
- [ ] `just test-swift` passes before changes

---

### Task 1: `AppSettings.launchAtLogin` persistence (TDD)

**Files:**
- Modify: `AppleBridge/Models/AppSettings.swift`
- Modify: `AppleBridgeTests/AppSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `AppleBridgeTests/AppSettingsTests.swift`:

```swift
@Test
@MainActor
func launchAtLoginDefaultsToFalseOnFreshInstall() throws {
    let suiteName = "AppSettingsTests.launchAtLoginDefault"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)

    let appSettings = AppSettings(defaults: defaults)

    #expect(appSettings.launchAtLogin == false)
}

@Test
@MainActor
func launchAtLoginPersistsAcrossInstances() throws {
    let suiteName = "AppSettingsTests.launchAtLoginPersist"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)

    let appSettings = AppSettings(defaults: defaults)
    appSettings.launchAtLogin = true

    let reloaded = AppSettings(defaults: defaults)

    #expect(reloaded.launchAtLogin == true)
    #expect(defaults.bool(forKey: "launchAtLogin"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test-swift`

Expected: FAIL — `AppSettings` has no member `launchAtLogin`

- [ ] **Step 3: Implement minimal persistence**

In `AppleBridge/Models/AppSettings.swift`, extend `Keys`:

```swift
static let launchAtLogin = "launchAtLogin"
```

Add property (same pattern as `mcpEnabled`):

```swift
var launchAtLogin: Bool {
    didSet {
        guard launchAtLogin != oldValue else { return }
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
    }
}
```

In `init`, after `mcpEnabled` load:

```swift
launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test-swift`

Expected: PASS (including new `AppSettings` tests)

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Models/AppSettings.swift AppleBridgeTests/AppSettingsTests.swift
git commit -m "feat: persist launchAtLogin in AppSettings"
```

---

### Task 2: Launch-at-login service layer

**Files:**
- Create: `AppleBridge/Services/LaunchAtLoginManaging.swift`
- Create: `AppleBridge/Services/SMAppLaunchAtLoginService.swift`
- Modify: `project.yml`
- Regenerate: `AppleBridge.xcodeproj`

- [ ] **Step 1: Add protocol and error type**

Create `AppleBridge/Services/LaunchAtLoginManaging.swift`:

```swift
import Foundation

enum LaunchAtLoginError: LocalizedError {
    case registrationFailed
    case unregistrationFailed

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            "Could not enable launch at login. Try again or check System Settings."
        case .unregistrationFailed:
            "Could not disable launch at login. Try again or check System Settings."
        }
    }
}

protocol LaunchAtLoginManaging {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}
```

- [ ] **Step 2: Implement production service**

Create `AppleBridge/Services/SMAppLaunchAtLoginService.swift`:

```swift
import Foundation
import ServiceManagement

@MainActor
final class SMAppLaunchAtLoginService: LaunchAtLoginManaging {
    var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func register() throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw LaunchAtLoginError.registrationFailed
        }
    }

    func unregister() throws {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            throw LaunchAtLoginError.unregistrationFailed
        }
    }
}
```

- [ ] **Step 3: Link ServiceManagement in Xcode project**

In `project.yml`, under `AppleBridge` target `dependencies`, add:

```yaml
      - sdk: ServiceManagement.framework
```

Run: `xcodegen generate`

- [ ] **Step 4: Verify build**

Run: `xcodebuild build -project AppleBridge.xcodeproj -scheme AppleBridge -destination 'platform=macOS' -quiet`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Services/LaunchAtLoginManaging.swift \
        AppleBridge/Services/SMAppLaunchAtLoginService.swift \
        project.yml AppleBridge.xcodeproj/project.pbxproj
git commit -m "feat: add SMAppService launch-at-login service"
```

---

### Task 3: Test seam — `MockLaunchAtLoginService`

**Files:**
- Create: `AppleBridgeTests/MockLaunchAtLoginService.swift`

- [ ] **Step 1: Create mock**

```swift
@testable import AppleBridge
import Foundation

@MainActor
final class MockLaunchAtLoginService: LaunchAtLoginManaging {
    var isRegistered = false
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        isRegistered = true
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        isRegistered = false
    }
}
```

- [ ] **Step 2: Verify test target compiles**

Run: `xcodebuild build-for-testing -project AppleBridge.xcodeproj -scheme AppleBridge -destination 'platform=macOS' -quiet`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add AppleBridgeTests/MockLaunchAtLoginService.swift
git commit -m "test: add MockLaunchAtLoginService"
```

---

### Task 4: `SettingsStore` orchestration (TDD)

**Files:**
- Modify: `AppleBridge/Models/SettingsStore.swift`
- Modify: `AppleBridgeTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `AppleBridgeTests/SettingsStoreTests.swift`:

```swift
@Test
@MainActor
func applyLaunchAtLoginChangeEnableRegistersAndPersists() async throws {
    let suiteName = "SettingsStoreTests.launchAtLoginEnable"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let appSettings = AppSettings(defaults: defaults)

    let launchAtLoginMock = MockLaunchAtLoginService()
    let mock = MockServerService()
    let serverStore = ServerStore(serverService: mock)
    let settingsStore = SettingsStore(
        appSettings: appSettings,
        serverStore: serverStore,
        launchAtLoginService: launchAtLoginMock
    )

    await settingsStore.applyLaunchAtLoginChange(true)

    #expect(launchAtLoginMock.registerCallCount == 1)
    #expect(appSettings.launchAtLogin)
    #expect(settingsStore.launchAtLoginError == nil)
}

@Test
@MainActor
func applyLaunchAtLoginChangeDisableUnregistersAndPersists() async throws {
    let suiteName = "SettingsStoreTests.launchAtLoginDisable"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let appSettings = AppSettings(defaults: defaults)
    appSettings.launchAtLogin = true

    let launchAtLoginMock = MockLaunchAtLoginService()
    launchAtLoginMock.isRegistered = true
    let mock = MockServerService()
    let serverStore = ServerStore(serverService: mock)
    let settingsStore = SettingsStore(
        appSettings: appSettings,
        serverStore: serverStore,
        launchAtLoginService: launchAtLoginMock
    )

    await settingsStore.applyLaunchAtLoginChange(false)

    #expect(launchAtLoginMock.unregisterCallCount == 1)
    #expect(!appSettings.launchAtLogin)
    #expect(settingsStore.launchAtLoginError == nil)
}

@Test
@MainActor
func applyLaunchAtLoginChangeEnableFailureLeavesSettingFalseAndSetsError() async throws {
    let suiteName = "SettingsStoreTests.launchAtLoginEnableFail"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let appSettings = AppSettings(defaults: defaults)

    let launchAtLoginMock = MockLaunchAtLoginService()
    launchAtLoginMock.registerError = LaunchAtLoginError.registrationFailed
    let settingsStore = SettingsStore(
        appSettings: appSettings,
        serverStore: ServerStore(serverService: MockServerService()),
        launchAtLoginService: launchAtLoginMock
    )

    await settingsStore.applyLaunchAtLoginChange(true)

    #expect(launchAtLoginMock.registerCallCount == 1)
    #expect(!appSettings.launchAtLogin)
    #expect(settingsStore.launchAtLoginError != nil)
}

@Test
@MainActor
func applyLaunchAtLoginChangeDisableFailureLeavesSettingTrueAndSetsError() async throws {
    let suiteName = "SettingsStoreTests.launchAtLoginDisableFail"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let appSettings = AppSettings(defaults: defaults)
    appSettings.launchAtLogin = true

    let launchAtLoginMock = MockLaunchAtLoginService()
    launchAtLoginMock.isRegistered = true
    launchAtLoginMock.unregisterError = LaunchAtLoginError.unregistrationFailed
    let settingsStore = SettingsStore(
        appSettings: appSettings,
        serverStore: ServerStore(serverService: MockServerService()),
        launchAtLoginService: launchAtLoginMock
    )

    await settingsStore.applyLaunchAtLoginChange(false)

    #expect(launchAtLoginMock.unregisterCallCount == 1)
    #expect(appSettings.launchAtLogin)
    #expect(settingsStore.launchAtLoginError != nil)
}

@Test
@MainActor
func performLaunchAtLoginReconcileSyncsSettingToSystemWhenSystemOff() async throws {
    let suiteName = "SettingsStoreTests.launchAtLoginReconcileOff"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let appSettings = AppSettings(defaults: defaults)
    appSettings.launchAtLogin = true

    let launchAtLoginMock = MockLaunchAtLoginService()
    launchAtLoginMock.isRegistered = false
    let settingsStore = SettingsStore(
        appSettings: appSettings,
        serverStore: ServerStore(serverService: MockServerService()),
        launchAtLoginService: launchAtLoginMock
    )

    await settingsStore.performLaunchAtLoginReconcileIfNeeded()

    #expect(!appSettings.launchAtLogin)
    #expect(settingsStore.launchAtLoginError == nil)
}

@Test
@MainActor
func performLaunchAtLoginReconcileSyncsSettingToSystemWhenSystemOn() async throws {
    let suiteName = "SettingsStoreTests.launchAtLoginReconcileOn"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let appSettings = AppSettings(defaults: defaults)

    let launchAtLoginMock = MockLaunchAtLoginService()
    launchAtLoginMock.isRegistered = true
    let settingsStore = SettingsStore(
        appSettings: appSettings,
        serverStore: ServerStore(serverService: MockServerService()),
        launchAtLoginService: launchAtLoginMock
    )

    await settingsStore.performLaunchAtLoginReconcileIfNeeded()

    #expect(appSettings.launchAtLogin)
    #expect(settingsStore.launchAtLoginError == nil)
}

@Test
@MainActor
func performLaunchAtLoginReconcileIsIdempotent() async throws {
    let suiteName = "SettingsStoreTests.launchAtLoginReconcileIdempotent"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let appSettings = AppSettings(defaults: defaults)
    appSettings.launchAtLogin = true

    let launchAtLoginMock = MockLaunchAtLoginService()
    launchAtLoginMock.isRegistered = false
    let settingsStore = SettingsStore(
        appSettings: appSettings,
        serverStore: ServerStore(serverService: MockServerService()),
        launchAtLoginService: launchAtLoginMock
    )

    await settingsStore.performLaunchAtLoginReconcileIfNeeded()
    launchAtLoginMock.isRegistered = true
    await settingsStore.performLaunchAtLoginReconcileIfNeeded()

    #expect(!appSettings.launchAtLogin)
}

@Test
@MainActor
func launchAtLoginOnDoesNotForceMCPStartWhenDisabled() async throws {
    let suiteName = "SettingsStoreTests.launchAtLoginMCPIndependent"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let appSettings = AppSettings(defaults: defaults)
    appSettings.launchAtLogin = true
    appSettings.mcpEnabled = false

    let launchAtLoginMock = MockLaunchAtLoginService()
    launchAtLoginMock.isRegistered = true
    let mock = MockServerService()
    let serverStore = ServerStore(serverService: mock)
    let settingsStore = SettingsStore(
        appSettings: appSettings,
        serverStore: serverStore,
        launchAtLoginService: launchAtLoginMock
    )

    await settingsStore.performLaunchAtLoginReconcileIfNeeded()
    await settingsStore.performLaunchRestoreIfNeeded()

    #expect(appSettings.launchAtLogin)
    #expect(await mock.startCallCount == 0)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test-swift`

Expected: FAIL — `SettingsStore` missing `launchAtLoginService`, `applyLaunchAtLoginChange`, `performLaunchAtLoginReconcileIfNeeded`, `launchAtLoginError`

- [ ] **Step 3: Implement SettingsStore changes**

In `AppleBridge/Models/SettingsStore.swift`:

Add published error state:

```swift
private(set) var launchAtLoginError: String?
```

Add private idempotency flag and injected service:

```swift
private let launchAtLoginService: any LaunchAtLoginManaging
private var didPerformLaunchAtLoginReconcile = false
```

Extend `init`:

```swift
init(
    appSettings: AppSettings,
    serverStore: ServerStore,
    permissionService: any RemindersPermissionChecking = RemindersPermissionService(),
    launchAtLoginService: any LaunchAtLoginManaging = SMAppLaunchAtLoginService()
) {
    self.appSettings = appSettings
    self.serverStore = serverStore
    self.permissionService = permissionService
    self.launchAtLoginService = launchAtLoginService
}
```

Add methods:

```swift
func applyLaunchAtLoginChange(_ enabled: Bool) async {
    launchAtLoginError = nil

    do {
        if enabled {
            try launchAtLoginService.register()
            appSettings.launchAtLogin = true
        } else {
            try launchAtLoginService.unregister()
            appSettings.launchAtLogin = false
        }
    } catch {
        launchAtLoginError = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }
}

/// Reconciles persisted launch-at-login preference with system registration status.
/// Invoked from `AppleBridgeApp.init()` only — not from SwiftUI view lifecycle.
func performLaunchAtLoginReconcileIfNeeded() async {
    guard !didPerformLaunchAtLoginReconcile else { return }
    didPerformLaunchAtLoginReconcile = true

    let systemRegistered = launchAtLoginService.isRegistered
    if appSettings.launchAtLogin != systemRegistered {
        appSettings.launchAtLogin = systemRegistered
    }
    launchAtLoginError = nil
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just test-swift`

Expected: PASS (all `SettingsStore` launch-at-login tests)

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Models/SettingsStore.swift AppleBridgeTests/SettingsStoreTests.swift
git commit -m "feat: orchestrate launch at login in SettingsStore"
```

---

### Task 5: App launch hook

**Files:**
- Modify: `AppleBridge/AppleBridgeApp.swift`
- Modify: `AppleBridgeTests/SettingsStoreTests.swift` (optional ordering test)

- [ ] **Step 1: Add reconcile call before MCP restore**

In `AppleBridge/AppleBridgeApp.swift`, update the launch `Task`:

```swift
Task(priority: .userInitiated) { @MainActor in
    await settingsStore.performLaunchAtLoginReconcileIfNeeded()
    await settingsStore.performLaunchRestoreIfNeeded()
    await serverStore.refreshBearerToken()
    await serverStore.refreshStatus()
}
```

- [ ] **Step 2: Add launch-ordering test (mirror existing launchRestoreFailure test)**

Add to `SettingsStoreTests.swift`:

```swift
@Test
@MainActor
func launchReconcileRunsBeforeMCPRestore() async throws {
    let suiteName = "SettingsStoreTests.launchOrdering"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let appSettings = AppSettings(defaults: defaults)
    appSettings.launchAtLogin = true
    appSettings.mcpEnabled = true

    let launchAtLoginMock = MockLaunchAtLoginService()
    launchAtLoginMock.isRegistered = false
    let mock = MockServerService()
    let serverStore = ServerStore(serverService: mock)
    let settingsStore = SettingsStore(
        appSettings: appSettings,
        serverStore: serverStore,
        launchAtLoginService: launchAtLoginMock
    )

    await settingsStore.performLaunchAtLoginReconcileIfNeeded()
    await settingsStore.performLaunchRestoreIfNeeded()

    #expect(!appSettings.launchAtLogin)
    #expect(await mock.startCallCount == 0)
}
```

- [ ] **Step 3: Run tests**

Run: `just test-swift`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add AppleBridge/AppleBridgeApp.swift AppleBridgeTests/SettingsStoreTests.swift
git commit -m "feat: reconcile launch at login on app startup"
```

---

### Task 6: Settings UI — Startup section

**Files:**
- Modify: `AppleBridge/Views/Settings/MCPSettingsView.swift`

- [ ] **Step 1: Add Startup section at top of form**

Update `body` `Form` to list `startupSection` first:

```swift
Form {
    startupSection
    serverSection
    connectionSection
    authenticationSection
}
```

Add section and binding:

```swift
private var startupSection: some View {
    Section {
        Toggle("Launch at login", isOn: launchAtLoginBinding)
    } header: {
        Text("Startup")
    } footer: {
        VStack(alignment: .leading, spacing: 4) {
            Text("Starts Apple Bridge when you log in. MCP server starts only if you left it enabled.")
            if let error = settingsStore.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}

private var launchAtLoginBinding: Binding<Bool> {
    Binding(
        get: { settingsStore.appSettings.launchAtLogin },
        set: { newValue in
            Task { await settingsStore.applyLaunchAtLoginChange(newValue) }
        }
    )
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild build -project AppleBridge.xcodeproj -scheme AppleBridge -destination 'platform=macOS' -quiet`

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add AppleBridge/Views/Settings/MCPSettingsView.swift
git commit -m "feat: add Launch at login toggle to MCP settings"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run full Swift test suite**

Run: `just test-swift`

Expected: all tests PASS

- [ ] **Step 2: Run local CI subset**

Run: `just ci`

Expected: PASS (or macOS subset green if Rust unchanged)

- [ ] **Step 3: Manual smoke checklist**

| # | Step | Expected |
|---|------|----------|
| 1 | Fresh launch (or reset `launchAtLogin` key) | Toggle **off** |
| 2 | Enable Launch at login | Toggle on; no error |
| 3 | Quit and relaunch app | Toggle still **on** |
| 4 | MCP off → log out/in | App in menu bar; MCP **stopped** |
| 5 | MCP on → log out/in | App in menu bar; MCP **running** |
| 6 | Remove from System Settings → Login Items → relaunch | Toggle shows **off** |
| 7 | Console/logs during toggle | No bearer tokens logged |

- [ ] **Step 4: Final commit if any fixups**

Only if smoke or CI required small fixes.

---

## Spec Coverage Checklist

| Spec requirement | Task |
|------------------|------|
| `launchAtLogin` default false, persisted | Task 1 |
| `SMAppService.mainApp` register/unregister | Task 2 |
| Protocol seam + mock for CI | Tasks 2–3 |
| Toggle enable/disable orchestration | Task 4 |
| Registration failure → revert + error | Task 4 |
| Launch reconcile (system wins) | Tasks 4–5 |
| MCP restore unchanged / independent | Task 4 |
| Startup section on MCP tab | Task 6 |
| `just test-swift` / `just ci` | Task 7 |
| Manual smoke AC | Task 7 |

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-28-launch-at-login.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** — implement tasks in this session with checkpoints

Which approach?
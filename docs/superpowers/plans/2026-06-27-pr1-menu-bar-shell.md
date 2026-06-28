# PR 1: Menu Bar Shell + Reminders Permission — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a menu bar-only macOS app that shows reminders permission status and lets the user grant EventKit reminders access.

**Architecture:** Lean SwiftUI shell with `MenuBarExtra`, an `@Observable` `AppStore`, and a protocol-backed `RemindersPermissionService` that wraps `EKEventStore`. A pure status mapper keeps EventKit mapping unit-testable without live permission dialogs.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, EventKit, xcodegen (project bootstrap), macOS 26+

**Spec:** `docs/superpowers/specs/2026-06-27-pr1-menu-bar-shell-design.md`

**Branch:** `feat/pr1-menu-bar-shell`

---

## File Map

| File | Responsibility |
|------|----------------|
| `project.yml` | xcodegen project definition (agent app, deployment target, usage description) |
| `AppleBridge/AppleBridgeApp.swift` | `@main` entry, `MenuBarExtra` scene |
| `AppleBridge/Models/RemindersPermissionStatus.swift` | App permission enum + `EKAuthorizationStatus` mapper |
| `AppleBridge/Models/AppStore.swift` | `@Observable` UI state and actions |
| `AppleBridge/Services/RemindersPermissionChecking.swift` | Protocol seam for testing |
| `AppleBridge/Services/RemindersPermissionService.swift` | Live EventKit implementation |
| `AppleBridge/Views/MenuBarPopoverView.swift` | Minimal popover UI |
| `AppleBridgeTests/RemindersPermissionStatusTests.swift` | Mapper unit tests |
| `AppleBridgeTests/AppStoreTests.swift` | Store behavior tests with mock service |
| `AppleBridgeTests/MockRemindersPermissionService.swift` | Test double |

---

### Task 1: Bootstrap Xcode project

**Files:**
- Create: `project.yml`
- Create: `AppleBridge/AppleBridgeApp.swift` (minimal stub)
- Create: `AppleBridgeTests/PlaceholderTests.swift` (removed in Task 2)

- [ ] **Step 1: Install xcodegen if missing**

Run:
```bash
which xcodegen || brew install xcodegen
```
Expected: path to `xcodegen` binary

- [ ] **Step 2: Create `project.yml`**

```yaml
name: AppleBridge
options:
  bundleIdPrefix: com.applebridge
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MACOSX_DEPLOYMENT_TARGET: "26.0"
targets:
  AppleBridge:
    type: application
    platform: macOS
    sources:
      - path: AppleBridge
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.applebridge.AppleBridge
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_LSUIElement: YES
        INFOPLIST_KEY_NSRemindersUsageDescription: "Apple Bridge needs access to your reminders to expose them through the local MCP bridge."
        INFOPLIST_KEY_CFBundleDisplayName: Apple Bridge
  AppleBridgeTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: AppleBridgeTests
    dependencies:
      - target: AppleBridge
```

- [ ] **Step 3: Create minimal app stub**

Create `AppleBridge/AppleBridgeApp.swift`:

```swift
import SwiftUI

@main
struct AppleBridgeApp: App {
    var body: some Scene {
        MenuBarExtra("Apple Bridge", systemImage: "bell") {
            Text("Apple Bridge")
        }
    }
}
```

Create `AppleBridgeTests/PlaceholderTests.swift`:

```swift
import Testing

@Suite("Placeholder")
struct PlaceholderTests {
    @Test func placeholder() {
        #expect(true)
    }
}
```

- [ ] **Step 4: Generate and build**

Run:
```bash
cd /Users/rcanoff/Projects/apple-bridge
xcodegen generate
xcodebuild build -project AppleBridge.xcodeproj -scheme AppleBridge -destination 'platform=macOS' -quiet
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add project.yml AppleBridge/ AppleBridgeTests/ AppleBridge.xcodeproj/
git commit -m "chore: bootstrap AppleBridge Xcode project"
```

---

### Task 2: Reminders permission status model (TDD)

**Files:**
- Create: `AppleBridge/Models/RemindersPermissionStatus.swift`
- Create: `AppleBridgeTests/RemindersPermissionStatusTests.swift`
- Delete: `AppleBridgeTests/PlaceholderTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `AppleBridgeTests/RemindersPermissionStatusTests.swift`:

```swift
import EventKit
import Testing
@testable import AppleBridge

@Suite("RemindersPermissionStatusMapper")
struct RemindersPermissionStatusTests {
    @Test func mapsNotDetermined() {
        #expect(
            RemindersPermissionStatusMapper.map(.notDetermined) == .notDetermined
        )
    }

    @Test func mapsFullAccessToAuthorized() {
        #expect(
            RemindersPermissionStatusMapper.map(.fullAccess) == .authorized
        )
    }

    @Test func mapsWriteOnlyToAuthorized() {
        #expect(
            RemindersPermissionStatusMapper.map(.writeOnly) == .authorized
        )
    }

    @Test func mapsDenied() {
        #expect(
            RemindersPermissionStatusMapper.map(.denied) == .denied
        )
    }

    @Test func mapsRestricted() {
        #expect(
            RemindersPermissionStatusMapper.map(.restricted) == .restricted
        )
    }

    @Test func displayNameIsNonEmptyForAllCases() {
        for status in RemindersPermissionStatus.allCases {
            #expect(!status.displayName.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
TZ=UTC xcodebuild test -project AppleBridge.xcodeproj -scheme AppleBridge \
  -only-testing:AppleBridgeTests/RemindersPermissionStatusTests \
  -destination 'platform=macOS' -quiet
```
Expected: FAIL — `RemindersPermissionStatusMapper` not found

- [ ] **Step 3: Write minimal implementation**

Create `AppleBridge/Models/RemindersPermissionStatus.swift`:

```swift
import EventKit
import Foundation

enum RemindersPermissionStatus: Equatable, CaseIterable, Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case restricted

    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .notDetermined:
            return "Not Determined"
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }
}

enum RemindersPermissionStatusMapper {
    static func map(_ status: EKAuthorizationStatus) -> RemindersPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .writeOnly:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }
}
```

Delete `AppleBridgeTests/PlaceholderTests.swift`.

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
TZ=UTC xcodebuild test -project AppleBridge.xcodeproj -scheme AppleBridge \
  -only-testing:AppleBridgeTests/RemindersPermissionStatusTests \
  -destination 'platform=macOS' -quiet
```
Expected: tests pass

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Models/RemindersPermissionStatus.swift \
  AppleBridgeTests/RemindersPermissionStatusTests.swift
git rm -f AppleBridgeTests/PlaceholderTests.swift 2>/dev/null || true
git commit -m "feat: add reminders permission status model and mapper"
```

---

### Task 3: Permission service protocol and live implementation (TDD)

**Files:**
- Create: `AppleBridge/Services/RemindersPermissionChecking.swift`
- Create: `AppleBridge/Services/RemindersPermissionService.swift`
- Create: `AppleBridgeTests/MockRemindersPermissionService.swift`

- [ ] **Step 1: Write the protocol and mock**

Create `AppleBridge/Services/RemindersPermissionChecking.swift`:

```swift
import Foundation

protocol RemindersPermissionChecking: Sendable {
    func currentStatus() -> RemindersPermissionStatus
    func requestAccess() async throws -> RemindersPermissionStatus
}
```

Create `AppleBridgeTests/MockRemindersPermissionService.swift`:

```swift
import Foundation
@testable import AppleBridge

final class MockRemindersPermissionService: RemindersPermissionChecking, @unchecked Sendable {
    var status: RemindersPermissionStatus = .notDetermined
    var requestResult: Result<RemindersPermissionStatus, Error> = .success(.authorized)
    private(set) var requestCallCount = 0

    func currentStatus() -> RemindersPermissionStatus {
        status
    }

    func requestAccess() async throws -> RemindersPermissionStatus {
        requestCallCount += 1
        return try requestResult.get()
    }
}
```

- [ ] **Step 2: Write live EventKit service**

Create `AppleBridge/Services/RemindersPermissionService.swift`:

```swift
import EventKit
import Foundation

enum RemindersPermissionError: LocalizedError, Equatable {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return message
        }
    }
}

final class RemindersPermissionService: RemindersPermissionChecking, @unchecked Sendable {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func currentStatus() -> RemindersPermissionStatus {
        let ekStatus = EKEventStore.authorizationStatus(for: .reminder)
        return RemindersPermissionStatusMapper.map(ekStatus)
    }

    func requestAccess() async throws -> RemindersPermissionStatus {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(
                        throwing: RemindersPermissionError.requestFailed(error.localizedDescription)
                    )
                    return
                }

                if granted {
                    continuation.resume(returning: .authorized)
                } else {
                    continuation.resume(returning: .denied)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
xcodebuild build -project AppleBridge.xcodeproj -scheme AppleBridge \
  -destination 'platform=macOS' -quiet
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add AppleBridge/Services/ AppleBridgeTests/MockRemindersPermissionService.swift
git commit -m "feat: add reminders permission service with test seam"
```

---

### Task 4: AppStore (TDD)

**Files:**
- Create: `AppleBridge/Models/AppStore.swift`
- Create: `AppleBridgeTests/AppStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `AppleBridgeTests/AppStoreTests.swift`:

```swift
import Testing
@testable import AppleBridge

@Suite("AppStore")
struct AppStoreTests {
    @Test
    @MainActor
    func refreshStatusUpdatesPermissionStatus() {
        let mock = MockRemindersPermissionService()
        mock.status = .denied
        let store = AppStore(permissionService: mock)

        store.refreshStatus()

        #expect(store.permissionStatus == .denied)
    }

    @Test
    @MainActor
    func requestAccessUpdatesStatusOnSuccess() async {
        let mock = MockRemindersPermissionService()
        mock.status = .notDetermined
        mock.requestResult = .success(.authorized)
        let store = AppStore(permissionService: mock)

        await store.requestAccess()

        #expect(store.permissionStatus == .authorized)
        #expect(store.isRequestingPermission == false)
        #expect(store.lastError == nil)
        #expect(mock.requestCallCount == 1)
    }

    @Test
    @MainActor
    func requestAccessSetsErrorOnFailure() async {
        let mock = MockRemindersPermissionService()
        mock.requestResult = .failure(
            RemindersPermissionError.requestFailed("permission denied by user")
        )
        let store = AppStore(permissionService: mock)

        await store.requestAccess()

        #expect(store.lastError == "permission denied by user")
        #expect(store.isRequestingPermission == false)
    }

    @Test
    @MainActor
    func requestAccessTogglesLoadingState() async {
        let mock = MockRemindersPermissionService()
        let store = AppStore(permissionService: mock)

        let task = Task { await store.requestAccess() }
        // Yield so requestAccess can set isRequestingPermission before finishing.
        await Task.yield()
        await task.value

        #expect(store.isRequestingPermission == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
TZ=UTC xcodebuild test -project AppleBridge.xcodeproj -scheme AppleBridge \
  -only-testing:AppleBridgeTests/AppStoreTests \
  -destination 'platform=macOS' -quiet
```
Expected: FAIL — `AppStore` not found

- [ ] **Step 3: Write minimal implementation**

Create `AppleBridge/Models/AppStore.swift`:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AppStore {
    private(set) var permissionStatus: RemindersPermissionStatus = .unknown
    private(set) var isRequestingPermission = false
    private(set) var lastError: String?

    private let permissionService: any RemindersPermissionChecking

    init(permissionService: any RemindersPermissionChecking = RemindersPermissionService()) {
        self.permissionService = permissionService
    }

    func refreshStatus() {
        lastError = nil
        permissionStatus = permissionService.currentStatus()
    }

    func requestAccess() async {
        guard !isRequestingPermission else { return }

        isRequestingPermission = true
        lastError = nil

        defer { isRequestingPermission = false }

        do {
            permissionStatus = try await permissionService.requestAccess()
        } catch {
            lastError = error.localizedDescription
            refreshStatus()
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
TZ=UTC xcodebuild test -project AppleBridge.xcodeproj -scheme AppleBridge \
  -only-testing:AppleBridgeTests/AppStoreTests \
  -destination 'platform=macOS' -quiet
```
Expected: tests pass

- [ ] **Step 5: Commit**

```bash
git add AppleBridge/Models/AppStore.swift AppleBridgeTests/AppStoreTests.swift
git commit -m "feat: add AppStore for reminders permission state"
```

---

### Task 5: Menu bar popover view

**Files:**
- Create: `AppleBridge/Views/MenuBarPopoverView.swift`

- [ ] **Step 1: Write the popover view**

Create `AppleBridge/Views/MenuBarPopoverView.swift`:

```swift
import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Bridge")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Reminders Access")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(store.permissionStatus.displayName)
                    .font(.body)
                    .foregroundStyle(statusColor)
            }

            if let lastError = store.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if store.permissionStatus == .notDetermined {
                Button("Grant Access") {
                    Task { await store.requestAccess() }
                }
                .disabled(store.isRequestingPermission)
            }

            if store.permissionStatus == .denied {
                Button("Open System Settings") {
                    openRemindersPrivacySettings()
                }
            }

            if store.isRequestingPermission {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 260)
    }

    private var statusColor: Color {
        switch store.permissionStatus {
        case .authorized:
            return .green
        case .notDetermined, .unknown:
            return .orange
        case .denied, .restricted:
            return .red
        }
    }

    private func openRemindersPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Reminders"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run:
```bash
xcodebuild build -project AppleBridge.xcodeproj -scheme AppleBridge \
  -destination 'platform=macOS' -quiet
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add AppleBridge/Views/MenuBarPopoverView.swift
git commit -m "feat: add menu bar popover view for reminders permission"
```

---

### Task 6: Wire app entry point

**Files:**
- Modify: `AppleBridge/AppleBridgeApp.swift`

- [ ] **Step 1: Replace stub with full app entry**

Replace `AppleBridge/AppleBridgeApp.swift` with:

```swift
import SwiftUI

@main
struct AppleBridgeApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        MenuBarExtra("Apple Bridge", systemImage: "bell") {
            MenuBarPopoverView(store: store)
                .onAppear {
                    store.refreshStatus()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 2: Build and run all tests**

Run:
```bash
xcodebuild build -project AppleBridge.xcodeproj -scheme AppleBridge \
  -destination 'platform=macOS' -quiet

TZ=UTC xcodebuild test -project AppleBridge.xcodeproj -scheme AppleBridge \
  -only-testing:AppleBridgeTests \
  -destination 'platform=macOS' -quiet
```
Expected: build and all tests succeed

- [ ] **Step 3: Commit**

```bash
git add AppleBridge/AppleBridgeApp.swift
git commit -m "feat: wire menu bar app with reminders permission flow"
```

---

### Task 7: Manual smoke test and PR checklist

**Files:** none (verification only)

- [ ] **Step 1: Launch the app**

Run:
```bash
open /Users/rcanoff/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/AppleBridge.app
```
Or build-and-run from Xcode (⌘R).

Verify:
- Menu bar bell icon appears
- No dock icon (agent app / `LSUIElement`)

- [ ] **Step 2: Exercise permission flow**

1. Open popover — status reflects current system state
2. If `.notDetermined`, tap **Grant Access** — macOS permission dialog appears
3. Grant access — status shows **Authorized** (green), button hides
4. Revoke in System Settings → Privacy & Security → Reminders, relaunch app
5. Status shows **Denied** (red) with **Open System Settings** button

- [ ] **Step 3: Final PR checklist**

Confirm all spec success criteria:

- [ ] Menu bar-only agent app (no dock icon)
- [ ] Accurate reminders permission status on launch
- [ ] User can request reminders access from popover
- [ ] Denied state shows System Settings guidance
- [ ] `AppleBridgeTests` pass
- [ ] No Rust, MCP, or EventKit data operations in diff

- [ ] **Step 4: Commit any fixes from smoke test**

If smoke test reveals issues, fix and commit before opening PR.

---

## Self-Review (plan vs spec)

| Spec requirement | Plan task |
|------------------|-----------|
| Menu bar agent app | Task 1 (`LSUIElement`), Task 6 (`MenuBarExtra`) |
| Reminders permission status | Task 2 (model), Task 3 (service), Task 4 (store) |
| Grant Access button | Task 5 (popover) |
| Denied → System Settings | Task 5 (`openRemindersPrivacySettings`) |
| Swift tests with mocks | Tasks 2, 4, mock in Task 3 |
| No Rust/MCP/EventKit data | Enforced by file map scope |
| macOS 26+ deployment | Task 1 `project.yml` |
| `NSRemindersUsageDescription` | Task 1 `project.yml` |

No placeholders. All types and method names are consistent across tasks.
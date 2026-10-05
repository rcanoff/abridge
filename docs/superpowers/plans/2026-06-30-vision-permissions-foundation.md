# Vision MCP Capability Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Vision MCP capability scaffolding (#151) before any `vision.*` MCP tool.

**Architecture:** MCP-only model — `CapabilityCatalog.visionCapabilities` (unshipped), Settings UI group + Apple Permissions footer note, server gating via `AppSettings.serverEnabledMCPCapabilityIDs` (no authorization gate), and `VisionProvider` routing stub in `AppleProviderBridge`. No TCC plist keys or permission services.

**Tech Stack:** Swift 6, SwiftUI, Vision (stub only), Swift Testing

**Spec:** `docs/superpowers/specs/2026-06-30-vision-permissions-foundation-design.md`

---

### Task 1: CapabilityCatalog.visionCapabilities

**Files:**
- Modify: `ABridge/Models/CapabilityCatalog.swift`

- [ ] **Step 1: Add vision capabilities (all shipped: false)**

Append after `mapkitCapabilities`:

```swift
    static let visionCapabilities: [CapabilityDefinition] = [
        CapabilityDefinition(id: "vision-text", capabilityID: "vision.text", label: "Text", shipped: false),
        CapabilityDefinition(
            id: "vision-document",
            capabilityID: "vision.document",
            label: "Document",
            shipped: false
        ),
        CapabilityDefinition(
            id: "vision-barcodes",
            capabilityID: "vision.barcodes",
            label: "Barcodes",
            shipped: false
        ),
        CapabilityDefinition(id: "vision-faces", capabilityID: "vision.faces", label: "Faces", shipped: false),
    ]
```

- [ ] **Step 2: Commit**

```bash
git add ABridge/Models/CapabilityCatalog.swift
git commit -m "feat(vision): add visionCapabilities to CapabilityCatalog"
```

---

### Task 2: AppSettings + PermissionsStore server gating

**Files:**
- Modify: `ABridge/Models/AppSettings.swift`
- Modify: `ABridge/Models/PermissionsStore.swift`
- Create: `ABridgeTests/AppSettingsVisionTests.swift`
- Create: `ABridgeTests/PermissionsStoreVisionTests.swift`
- Modify: `ABridgeTests/AppSettingsTests.swift` (if assertions need vision baseline)
- Modify: `ABridgeTests/PermissionsStoreTests.swift` (if needed)

**Note:** New test files live under `ABridgeTests/` — picked up by existing `project.yml` source glob. No `project.yml` or `xcodegen` changes expected.

- [ ] **Step 1: Write failing gating tests**

`ABridgeTests/AppSettingsVisionTests.swift`:

```swift
@testable import ABridge
import Foundation
import Testing

@Suite("AppSettingsVision")
struct AppSettingsVisionTests {
    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsOmitsUnshippedVisionCapabilities() throws {
        let suiteName = "AppSettingsVisionTests.unshipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["vision-text", "vision-barcodes"])

        #expect(appSettings.enabledVisionCapabilityIDs.isEmpty)
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: false,
                eventsAuthorized: false,
                contactsAuthorized: false,
                locationAuthorized: false
            ) == ["diagnostics.read"]
        )
    }
}
```

`ABridgeTests/PermissionsStoreVisionTests.swift`:

```swift
@testable import ABridge
import Foundation
import Testing

@Suite("PermissionsStoreVision")
struct PermissionsStoreVisionTests {
    @Test
    @MainActor
    func shouldApplySavedCapabilitiesAfterEnablingUnshippedVisionToggle() throws {
        let suiteName = "PermissionsStoreVisionTests.unshippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "vision-text",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: false,
                    eventsAuthorized: false,
                    contactsAuthorized: false,
                    locationAuthorized: false
                )
            )
        )
    }

    @Test
    @MainActor
    func shouldApplySavedCapabilitiesAfterEnablingVisionDocumentToggle() throws {
        let suiteName = "PermissionsStoreVisionTests.documentApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "vision-document",
                authorization: ApplePermissionAuthorization(
                    remindersAuthorized: true,
                    eventsAuthorized: true,
                    contactsAuthorized: true,
                    locationAuthorized: true
                )
            )
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-swift`
Expected: FAIL — `enabledVisionCapabilityIDs` not found

- [ ] **Step 3: Extend AppSettings**

Add:

```swift
    var enabledVisionCapabilityIDs: [String] {
        CapabilityCatalog.visionCapabilities
            .filter { $0.shipped && savedCapabilityIDs.contains($0.id) }
            .map(\.capabilityID)
    }
```

Extend `serverEnabledMCPCapabilityIDs` body — append after mapkit block, before `return`:

```swift
        capabilities.append(contentsOf: enabledVisionCapabilityIDs)
```

Vision capabilities are **not** gated on any Apple authorization flag.

- [ ] **Step 4: Extend PermissionsStore**

Add vision branch in `shouldApplySavedCapabilitiesAfterToggle` **before** the final `return authorization.remindersAuthorized`:

```swift
        if CapabilityCatalog.visionCapabilities.contains(where: { $0.id == capabilityID && $0.shipped }) {
            return true
        }

        if CapabilityCatalog.visionCapabilities.contains(where: { $0.id == capabilityID }) {
            return true
        }
```

The second branch covers unshipped toggles (persist + optional server reapply without blocking on reminders authorization). Consolidate to a single vision branch if both shipped and unshipped should behave identically:

```swift
        if CapabilityCatalog.visionCapabilities.contains(where: { $0.id == capabilityID }) {
            return true
        }
```

Do **not** add `requiresAppleVisionAccess`.

- [ ] **Step 5: Run tests**

Run: `just test-swift`
Expected: PASS AppSettingsVision and PermissionsStoreVision suites

- [ ] **Step 6: Commit**

```bash
git add ABridge/Models/AppSettings.swift ABridge/Models/PermissionsStore.swift \
        ABridgeTests/AppSettingsVisionTests.swift ABridgeTests/PermissionsStoreVisionTests.swift
git commit -m "feat(vision): wire vision capability gating in AppSettings and PermissionsStore"
```

---

### Task 3: VisionMCPPermissionsGroup + PermissionsSettingsView footer

**Files:**
- Modify: `ABridge/Views/Settings/PermissionsSettingsComponents.swift`
- Modify: `ABridge/Views/Settings/PermissionsSettingsView.swift`

- [ ] **Step 1: Add VisionMCPPermissionsGroup**

After `MapKitMCPPermissionsGroup` in `PermissionsSettingsComponents.swift`:

```swift
struct VisionMCPPermissionsGroup: View {
    let capabilityBinding: (String) -> Binding<Bool>

    var body: some View {
        Section {
            ForEach(CapabilityCatalog.visionCapabilities) { capability in
                Toggle(capability.label, isOn: capabilityBinding(capability.id))
            }
        } header: {
            Text("Vision")
        }
    }
}
```

- [ ] **Step 2: Wire Vision group in PermissionsSettingsView**

After `MapKitMCPPermissionsGroup` in the MCP Permissions section:

```swift
                VisionMCPPermissionsGroup { capabilityID in
                    binding(for: capabilityID)
                }
```

- [ ] **Step 3: Update Apple Permissions footer**

Replace or extend the existing footer text:

```swift
            } footer: {
                Text(
                    "To view or revoke what macOS has granted, use System Settings. "
                        + "Vision tools analyze image data supplied by MCP clients; "
                        + "no macOS privacy permission is required for this foundation."
                )
            }
```

- [ ] **Step 4: Run tests**

Run: `just test-swift`
Expected: PASS (UI-only change; no new compile errors)

- [ ] **Step 5: Commit**

```bash
git add ABridge/Views/Settings/PermissionsSettingsComponents.swift \
        ABridge/Views/Settings/PermissionsSettingsView.swift
git commit -m "feat(vision): add Vision MCP group and Apple Permissions footer note"
```

---

### Task 4: VisionProvider stub + AppleProviderBridge routing

**Files:**
- Create: `ABridge/Providers/Vision/VisionProvider.swift`
- Modify: `ABridge/Providers/AppleProviderBridge.swift`
- Create: `ABridgeTests/AppleProviderBridgeVisionTests.swift`

**Note:** `ABridge/Providers/Vision/` is under the existing `ABridge` source path — no `project.yml` edit required. If Xcode does not see new files, run `xcodegen generate` (should not be necessary with directory-based sources).

- [ ] **Step 1: Write failing bridge test**

```swift
@testable import ABridge
import Foundation
import Testing

@Suite("AppleProviderBridgeVision")
struct AppleProviderBridgeVisionTests {
    @Test
    func callProviderVisionReturnsUnknownOperation() throws {
        let bridge = AppleProviderBridge()
        let request = ProviderRequest(provider: "vision", operation: "recognize_text", payloadJson: "{}")
        let response = bridge.callProvider(request: request)
        #expect(response.ok == false)

        let errorJson = try #require(response.errorJson)
        let data = try #require(errorJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["code"] as? String == "unknown_operation")
        #expect((decoded?["message"] as? String)?.contains("recognize_text") == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-swift`
Expected: FAIL — `unknown_provider` or missing Vision routing

- [ ] **Step 3: Implement VisionProvider stub**

`ABridge/Providers/Vision/VisionProvider.swift`:

```swift
import Foundation

@MainActor
enum LiveVisionEnvironment {
    static let sharedProvider = VisionProvider()
}

@MainActor
struct VisionProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        let payload: [String: String] = [
            "code": "unknown_operation",
            "message": "Unknown vision operation: \(operation)",
        ]
        let errorJson = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"code":"unknown_operation"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
    }
}
```

- [ ] **Step 4: Add vision case to AppleProviderBridge**

Add factory property and init parameter:

```swift
    private let makeVisionProvider: @MainActor @Sendable () -> VisionProvider
```

Default: `{ LiveVisionEnvironment.sharedProvider }`

Add test seam:

```swift
    @MainActor
    convenience init(visionProvider: VisionProvider) {
        self.init(makeVisionProvider: { [visionProvider] in visionProvider })
    }
```

Extend primary `init` to accept `makeVisionProvider` (mirror `makeMapKitProvider` pattern).

Add routing case before `default`:

```swift
        case "vision":
            return Self.performOnMainActor { [makeVisionProvider] in
                let provider = makeVisionProvider()
                return provider.handle(operation: request.operation, payloadJson: request.payloadJson)
            }
```

- [ ] **Step 5: Run tests**

Run: `just test-swift`
Expected: PASS AppleProviderBridgeVision suite

- [ ] **Step 6: Commit**

```bash
git add ABridge/Providers/Vision/VisionProvider.swift \
        ABridge/Providers/AppleProviderBridge.swift \
        ABridgeTests/AppleProviderBridgeVisionTests.swift
git commit -m "feat(vision): add VisionProvider stub and bridge routing"
```

---

### Task 5: Final verification

- [ ] **Step 1: Confirm no project.yml changes**

Run: `git diff main -- project.yml`
Expected: no diff (no TCC usage strings for payload-only V1)

- [ ] **Step 2: Run full Swift test suite**

```bash
TZ=UTC just test-swift
```

Expected: all tests pass

- [ ] **Step 3: Fix any failures and commit**

If `xcodegen generate` was run due to unexpected project drift:

```bash
git add project.yml ABridge.xcodeproj
git commit -m "chore(vision): regenerate Xcode project"
```
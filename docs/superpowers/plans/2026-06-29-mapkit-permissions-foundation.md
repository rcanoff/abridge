# MapKit Location Permission & MCP Capability Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship MapKit/CoreLocation Apple permission + MCP capability scaffolding (#150) before any `mapkit.*` MCP tool.

**Architecture:** Mirror Contacts two-layer model — `LocationPermissionService` for CoreLocation when-in-use TCC, `CapabilityCatalog.mapkitCapabilities` (unshipped), Settings UI rows, server gating via `AppSettings.serverEnabledMCPCapabilityIDs`, and `MapKitProvider` routing stub in `AppleProviderBridge`.

**Tech Stack:** Swift 6, SwiftUI, CoreLocation, Swift Testing, xcodegen

**Spec:** `docs/superpowers/specs/2026-06-29-mapkit-permissions-foundation-design.md`

---

### Task 1: NSLocationUsageDescription in project.yml

**Files:**
- Modify: `project.yml`
- Regenerate: `ABridge.xcodeproj` via xcodegen

- [ ] **Step 1: Add usage description**

In `project.yml` under `ABridge` target `settings.base`, after `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription`:

```yaml
        INFOPLIST_KEY_NSLocationUsageDescription: "ABridge needs access to your location to expose MapKit capabilities such as nearby search, routing, and current location through the local MCP bridge."
```

- [ ] **Step 2: Regenerate Xcode project**

Run: `xcodegen generate`
Expected: `ABridge.xcodeproj` updated with `INFOPLIST_KEY_NSLocationUsageDescription`

- [ ] **Step 3: Commit**

```bash
git add project.yml ABridge.xcodeproj
git commit -m "feat(mapkit): add NSLocationUsageDescription to project.yml"
```

---

### Task 2: LocationPermissionStatus + mapper

**Files:**
- Create: `ABridge/Models/LocationPermissionStatus.swift`
- Create: `ABridgeTests/LocationPermissionStatusTests.swift`

- [ ] **Step 1: Write failing mapper tests**

```swift
@testable import ABridge
import CoreLocation
import Testing

@Suite("LocationPermissionStatus")
struct LocationPermissionStatusTests {
    @Test
    func mapNotDetermined() {
        #expect(LocationPermissionStatusMapper.map(.notDetermined) == .notDetermined)
    }

    @Test
    func mapAuthorizedGrantsReadAccess() {
        let status = LocationPermissionStatusMapper.map(.authorized)
        #expect(status == .authorized)
        #expect(status.grantsReadAccess)
    }

    @Test
    func mapAuthorizedAlwaysGrantsReadAccess() {
        let status = LocationPermissionStatusMapper.map(.authorizedAlways)
        #expect(status == .authorizedAlways)
        #expect(status.grantsReadAccess)
    }

    @Test
    func mapDeniedDoesNotGrantReadAccess() {
        let status = LocationPermissionStatusMapper.map(.denied)
        #expect(status.grantsReadAccess == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-swift`
Expected: FAIL — `LocationPermissionStatusMapper` not found

- [ ] **Step 3: Implement status + mapper**

```swift
import CoreLocation
import Foundation

enum LocationPermissionStatus: Equatable, CaseIterable {
    case unknown
    case notDetermined
    case authorized
    case authorizedAlways
    case denied
    case restricted

    var grantsReadAccess: Bool {
        switch self {
        case .authorized, .authorizedAlways:
            true
        default:
            false
        }
    }

    var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .notDetermined: "Not Determined"
        case .authorized: "Authorized"
        case .authorizedAlways: "Authorized Always"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }
}

enum LocationPermissionStatusMapper {
    static func map(_ status: CLAuthorizationStatus) -> LocationPermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .authorizedAlways: .authorizedAlways
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `just test-swift`
Expected: PASS LocationPermissionStatus suite

- [ ] **Step 5: Commit**

```bash
git add ABridge/Models/LocationPermissionStatus.swift ABridgeTests/LocationPermissionStatusTests.swift
git commit -m "feat(mapkit): add LocationPermissionStatus and mapper"
```

---

### Task 3: LocationPermissionService

**Files:**
- Create: `ABridge/Services/LocationPermissionChecking.swift`
- Create: `ABridge/Services/LocationPermissionService.swift`
- Create: `ABridgeTests/LocationPermissionServiceTests.swift`
- Create: `ABridgeTests/MockLocationPermissionService.swift`

- [ ] **Step 1: Write failing service tests**

```swift
@testable import ABridge
import CoreLocation
import Testing

@Suite("LocationPermissionService")
struct LocationPermissionServiceTests {
    @Test
    @MainActor
    func currentStatusMapsAuthorizationStatus() {
        let service = LocationPermissionService(
            authorizationStatusProvider: { .authorizedAlways }
        )
        #expect(service.currentStatus() == .authorizedAlways)
    }

    @Test
    @MainActor
    func requestAccessReturnsHandlerResult() async throws {
        let service = LocationPermissionService(
            authorizationStatusProvider: { .notDetermined },
            requestAccessHandler: { .authorized }
        )
        let result = try await service.requestAccess()
        #expect(result == .authorized)
        #expect(service.currentStatus() == .authorized)
    }

    @Test
    @MainActor
    func requestAccessSurfacesError() async {
        let service = LocationPermissionService(
            requestAccessHandler: { throw LocationPermissionError.requestFailed("denied") }
        )
        await #expect(throws: LocationPermissionError.self) {
            _ = try await service.requestAccess()
        }
    }

    @Test
    @MainActor
    func currentStatusUsesSessionGrantWhenAuthorizationStillNotDetermined() {
        let service = LocationPermissionService(
            authorizationStatusProvider: { .notDetermined },
            requestAccessHandler: { .authorized }
        )
        Task {
            _ = try? await service.requestAccess()
        }
        // After request, session grant should surface even if provider still returns notDetermined
        let serviceWithSession = LocationPermissionService(
            authorizationStatusProvider: { .notDetermined },
            requestAccessHandler: { .authorized }
        )
        _ = try? await serviceWithSession.requestAccess()
        #expect(serviceWithSession.currentStatus().grantsReadAccess)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test-swift`
Expected: FAIL

- [ ] **Step 3: Implement protocol + service**

`LocationPermissionChecking.swift`:

```swift
import Foundation

@MainActor
protocol LocationPermissionChecking {
    func currentStatus() -> LocationPermissionStatus
    func requestAccess() async throws -> LocationPermissionStatus
}
```

`LocationPermissionService.swift`:

```swift
import CoreLocation
import Foundation

enum LocationPermissionError: LocalizedError, Equatable {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(message):
            message
        }
    }
}

@MainActor
final class LocationPermissionService: LocationPermissionChecking {
    typealias AuthorizationStatusProvider = @MainActor () -> CLAuthorizationStatus
    typealias RequestAccessHandler = @MainActor () async throws -> LocationPermissionStatus

    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let requestAccessHandler: RequestAccessHandler
    private var sessionStatus: LocationPermissionStatus?

    init(
        authorizationStatusProvider: AuthorizationStatusProvider? = nil,
        requestAccessHandler: RequestAccessHandler? = nil
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider ?? {
            CLLocationManager().authorizationStatus
        }
        self.requestAccessHandler = requestAccessHandler ?? {
            try await Self.requestAccess()
        }
    }

    func currentStatus() -> LocationPermissionStatus {
        let mapped = LocationPermissionStatusMapper.map(authorizationStatusProvider())
        if mapped != .notDetermined {
            sessionStatus = nil
            return mapped
        }
        return sessionStatus ?? mapped
    }

    func requestAccess() async throws -> LocationPermissionStatus {
        let result = try await requestAccessHandler()
        if result.grantsReadAccess {
            sessionStatus = result
        } else {
            sessionStatus = nil
        }
        return result
    }

    private static func requestAccess() async throws -> LocationPermissionStatus {
        try await AuthorizationRequestLocationManager().requestWhenInUseAuthorization()
    }
}

@MainActor
private final class AuthorizationRequestLocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationPermissionStatus, Error>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUseAuthorization() async throws -> LocationPermissionStatus {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestWhenInUseAuthorization()
            resumeIfDetermined()
        }
    }

    func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        resumeIfDetermined()
    }

    private func resumeIfDetermined() {
        let status = LocationPermissionStatusMapper.map(manager.authorizationStatus)
        guard status != .notDetermined, let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: status)
    }
}
```

`MockLocationPermissionService.swift`:

```swift
@testable import ABridge
import Foundation

@MainActor
final class MockLocationPermissionService: LocationPermissionChecking {
    var status: LocationPermissionStatus = .notDetermined
    var requestResult: Result<LocationPermissionStatus, Error> = .success(.authorized)
    private(set) var requestCallCount = 0

    func currentStatus() -> LocationPermissionStatus {
        status
    }

    func requestAccess() async throws -> LocationPermissionStatus {
        requestCallCount += 1
        let result = try requestResult.get()
        status = result
        return result
    }
}
```

- [ ] **Step 4: Run tests**

Run: `just test-swift`
Expected: PASS LocationPermissionService suite

- [ ] **Step 5: Commit**

```bash
git add ABridge/Services/LocationPermissionChecking.swift \
        ABridge/Services/LocationPermissionService.swift \
        ABridgeTests/LocationPermissionServiceTests.swift \
        ABridgeTests/MockLocationPermissionService.swift
git commit -m "feat(mapkit): add LocationPermissionService with tests"
```

---

### Task 4: CapabilityCatalog.mapkitCapabilities

**Files:**
- Modify: `ABridge/Models/CapabilityCatalog.swift`

- [ ] **Step 1: Add mapkit capabilities (all shipped: false)**

Append after `contactsCapabilities`:

```swift
    static let mapkitCapabilities: [CapabilityDefinition] = [
        CapabilityDefinition(id: "mapkit-search", capabilityID: "mapkit.search", label: "Search", shipped: false),
        CapabilityDefinition(id: "mapkit-geocode", capabilityID: "mapkit.geocode", label: "Geocode", shipped: false),
        CapabilityDefinition(id: "mapkit-routing", capabilityID: "mapkit.routing", label: "Routing", shipped: false),
        CapabilityDefinition(
            id: "mapkit-navigation",
            capabilityID: "mapkit.navigation",
            label: "Navigation",
            shipped: false
        ),
        CapabilityDefinition(id: "corelocation-read", capabilityID: "corelocation.read", label: "Location", shipped: false),
        CapabilityDefinition(id: "mapkit-read", capabilityID: "mapkit.read", label: "Read", shipped: false),
    ]
```

- [ ] **Step 2: Commit**

```bash
git add ABridge/Models/CapabilityCatalog.swift
git commit -m "feat(mapkit): add mapkitCapabilities to CapabilityCatalog"
```

---

### Task 5: AppSettings + PermissionsStore server gating

**Files:**
- Modify: `ABridge/Models/AppSettings.swift`
- Modify: `ABridge/Models/PermissionsStore.swift`
- Create: `ABridgeTests/AppSettingsMapKitTests.swift`
- Create: `ABridgeTests/PermissionsStoreMapKitTests.swift`
- Modify: `ABridgeTests/AppSettingsTests.swift`
- Modify: `ABridgeTests/PermissionsStoreTests.swift`
- Modify: `ABridgeTests/PermissionsStoreContactsTests.swift`
- Modify: `ABridgeTests/AppSettingsContactsTests.swift`
- Modify: `ABridgeTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing gating tests**

`ABridgeTests/AppSettingsMapKitTests.swift`:

```swift
@testable import ABridge
import Foundation
import Testing

@Suite("AppSettingsMapKit")
struct AppSettingsMapKitTests {
    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsOmitsMapKitCapabilitiesWithoutAuthorization() throws {
        let suiteName = "AppSettingsMapKitTests.mapkitServerGating"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["mapkit-search"])

        #expect(appSettings.enabledMapKitCapabilityIDs.isEmpty)
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: false,
                eventsAuthorized: false,
                contactsAuthorized: false,
                locationAuthorized: false
            ) == ["diagnostics.read"]
        )
        #expect(
            appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: false,
                eventsAuthorized: false,
                contactsAuthorized: false,
                locationAuthorized: true
            ) == ["diagnostics.read"]
        )
    }
}
```

`ABridgeTests/PermissionsStoreMapKitTests.swift`:

```swift
@testable import ABridge
import Foundation
import Testing

@Suite("PermissionsStoreMapKit")
struct PermissionsStoreMapKitTests {
    @Test
    @MainActor
    func requiresAppleLocationAccessIsFalseForUnshippedMapKitToggle() throws {
        let suiteName = "PermissionsStoreMapKitTests.unshipped"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))
        store.setChecked(true, for: "mapkit-search")

        #expect(store.requiresAppleLocationAccess == false)
    }

    @Test
    @MainActor
    func shouldNotApplySavedCapabilitiesAfterEnablingUnshippedMapKitWithoutAuthorization() throws {
        let suiteName = "PermissionsStoreMapKitTests.unshippedApply"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = PermissionsStore(appSettings: AppSettings(defaults: defaults))

        #expect(
            store.shouldApplySavedCapabilitiesAfterToggle(
                enabling: true,
                capabilityID: "mapkit-search",
                remindersAuthorized: true,
                eventsAuthorized: true,
                contactsAuthorized: true,
                locationAuthorized: false
            )
        )
    }
}
```

- [ ] **Step 2: Extend AppSettings**

Add:

```swift
    var enabledMapKitCapabilityIDs: [String] {
        CapabilityCatalog.mapkitCapabilities
            .filter { $0.shipped && savedCapabilityIDs.contains($0.id) }
            .map(\.capabilityID)
    }
```

Extend signature and body:

```swift
    func serverEnabledMCPCapabilityIDs(
        remindersAuthorized: Bool,
        eventsAuthorized: Bool,
        contactsAuthorized: Bool,
        locationAuthorized: Bool
    ) -> [String] {
        var capabilities = ["diagnostics.read"]
        if remindersAuthorized {
            capabilities.append(contentsOf: enabledReminderCapabilityIDs)
        }
        if eventsAuthorized {
            capabilities.append(contentsOf: enabledCalendarCapabilityIDs)
            capabilities.append(contentsOf: enabledEventsCapabilityIDs)
        }
        if contactsAuthorized {
            capabilities.append(contentsOf: enabledContactsCapabilityIDs)
        }
        if locationAuthorized {
            capabilities.append(contentsOf: enabledMapKitCapabilityIDs)
        }
        return capabilities
    }
```

- [ ] **Step 3: Extend PermissionsStore**

Add:

```swift
    var requiresAppleLocationAccess: Bool {
        checkedCapabilityIDs.contains { id in
            CapabilityCatalog.mapkitCapabilities.contains { $0.id == id && $0.shipped }
        }
    }
```

Extend `shouldApplySavedCapabilitiesAfterToggle`:

```swift
    func shouldApplySavedCapabilitiesAfterToggle(
        enabling: Bool,
        capabilityID: String,
        remindersAuthorized: Bool,
        eventsAuthorized: Bool,
        contactsAuthorized: Bool,
        locationAuthorized: Bool
    ) -> Bool {
        guard enabling else { return true }

        if CapabilityCatalog.calendarsCapabilities.contains(where: { $0.id == capabilityID && $0.shipped }) {
            return eventsAuthorized
        }

        if CapabilityCatalog.eventsCapabilities.contains(where: { $0.id == capabilityID && $0.shipped }) {
            return eventsAuthorized
        }

        if CapabilityCatalog.contactsCapabilities.contains(where: { $0.id == capabilityID && $0.shipped }) {
            return contactsAuthorized
        }

        if CapabilityCatalog.mapkitCapabilities.contains(where: { $0.id == capabilityID && $0.shipped }) {
            return locationAuthorized
        }

        return remindersAuthorized
    }
```

- [ ] **Step 4: Update all call sites**

Run: `rg 'serverEnabledMCPCapabilityIDs|shouldApplySavedCapabilitiesAfterToggle|applySavedCapabilities' ABridge ABridgeTests`

Add `locationAuthorized: false` (or appropriate value) to every existing call site. Files include at minimum:

- `ABridge/Models/SettingsStore.swift`
- `ABridge/Views/Settings/PermissionsSettingsView.swift`
- `ABridgeTests/AppSettingsTests.swift`
- `ABridgeTests/AppSettingsContactsTests.swift`
- `ABridgeTests/PermissionsStoreTests.swift`
- `ABridgeTests/PermissionsStoreContactsTests.swift`
- `ABridgeTests/SettingsStoreTests.swift`

- [ ] **Step 5: Run tests**

Run: `just test-swift`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add ABridge/Models/AppSettings.swift ABridge/Models/PermissionsStore.swift \
        ABridgeTests/AppSettingsMapKitTests.swift ABridgeTests/PermissionsStoreMapKitTests.swift \
        ABridgeTests/AppSettingsTests.swift ABridgeTests/AppSettingsContactsTests.swift \
        ABridgeTests/PermissionsStoreTests.swift ABridgeTests/PermissionsStoreContactsTests.swift \
        ABridgeTests/SettingsStoreTests.swift
git commit -m "feat(mapkit): gate mapkit capabilities on location authorization"
```

---

### Task 6: SettingsStore + AppStore location wiring

**Files:**
- Modify: `ABridge/Models/SettingsStore.swift`
- Modify: `ABridge/Models/AppStore.swift`
- Modify: `ABridge/Services/ABridgeAppStoreMaking.swift`
- Modify: `ABridgeTests/SettingsStoreTests.swift`
- Modify: `ABridgeTests/MockABridgeAppStoreMaker.swift`
- Create or extend: `ABridgeTests/AppStoreLocationTests.swift`

- [ ] **Step 1: Write failing SettingsStore test**

Add to `ABridgeTests/SettingsStoreTests.swift`:

```swift
    @Test
    @MainActor
    func applySavedCapabilitiesPassesLocationAuthorizedToServer() async throws {
        let suiteName = "SettingsStoreTests.locationAuthorized"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        appSettings.mcpEnabled = true
        appSettings.saveCapabilityIDs(["mapkit-search"])

        let mock = MockServerService()
        let serverStore = ServerStore(serverService: mock)
        let locationService = MockLocationPermissionService()
        locationService.status = .authorized

        let settingsStore = SettingsStore(
            appSettings: appSettings,
            serverStore: serverStore,
            locationPermissionService: locationService
        )

        await settingsStore.applySavedCapabilities(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false,
            locationAuthorized: true
        )

        #expect(mock.lastRestartEnabledCapabilities == ["diagnostics.read"])
    }
```

Note: while `mapkit-search` is unshipped, server still receives only `diagnostics.read` — test documents gating; when a capability ships, extend assertion.

- [ ] **Step 2: Inject locationPermissionService into SettingsStore**

Add property and init parameter (default `LocationPermissionService()`):

```swift
    private let locationPermissionService: any LocationPermissionChecking
```

Extend `applySavedCapabilities`:

```swift
    func applySavedCapabilities(
        remindersAuthorized: Bool,
        eventsAuthorized: Bool,
        contactsAuthorized: Bool,
        locationAuthorized: Bool
    ) async {
        tokenResetNotice = nil
        guard appSettings.mcpEnabled else { return }

        await serverStore.restartServer(
            port: appSettings.mcpPort,
            enabledCapabilities: appSettings.serverEnabledMCPCapabilityIDs(
                remindersAuthorized: remindersAuthorized,
                eventsAuthorized: eventsAuthorized,
                contactsAuthorized: contactsAuthorized,
                locationAuthorized: locationAuthorized
            ),
            usageLoggingEnabled: appSettings.usageLoggingEnabled
        )
    }
```

Update `serverEnabledCapabilities`:

```swift
    private var serverEnabledCapabilities: [String] {
        appSettings.serverEnabledMCPCapabilityIDs(
            remindersAuthorized: permissionService.currentStatus().grantsReadAccess,
            eventsAuthorized: eventsPermissionService.currentStatus().grantsReadAccess,
            contactsAuthorized: contactsPermissionService.currentStatus().grantsReadAccess,
            locationAuthorized: locationPermissionService.currentStatus().grantsReadAccess
        )
    }
```

- [ ] **Step 3: Extend AppStore**

Add properties and methods mirroring contacts:

```swift
    private(set) var locationPermissionStatus: LocationPermissionStatus = .unknown
    private(set) var isRequestingLocationPermission = false
    private let locationPermissionService: any LocationPermissionChecking
```

Init parameter: `locationPermissionService: any LocationPermissionChecking = LocationPermissionService()`

In `refreshStatus()`:

```swift
        locationPermissionStatus = locationPermissionService.currentStatus()
```

Add:

```swift
    func refreshLocationStatus() {
        lastError = nil
        locationPermissionStatus = locationPermissionService.currentStatus()
    }

    func requestLocationAccess() async {
        guard !isRequestingLocationPermission else { return }

        isRequestingLocationPermission = true
        lastError = nil

        defer { isRequestingLocationPermission = false }

        do {
            locationPermissionStatus = try await locationPermissionService.requestAccess()
        } catch {
            refreshLocationStatus()
            lastError = error.localizedDescription
        }
    }

    func openLocationPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices"
        ) else {
            lastError = "Unable to open Location privacy settings."
            return
        }

        guard urlOpener.open(url) else {
            lastError = "Unable to open Location privacy settings."
            return
        }

        lastError = nil
    }
```

- [ ] **Step 4: Write AppStore location tests**

`ABridgeTests/AppStoreLocationTests.swift`:

```swift
@testable import ABridge
import Testing

@Suite("AppStoreLocation")
struct AppStoreLocationTests {
    @Test
    @MainActor
    func requestLocationAccessUpdatesStatus() async throws {
        let mock = MockLocationPermissionService()
        mock.requestResult = .success(.authorizedAlways)
        let store = AppStore(locationPermissionService: mock)

        await store.requestLocationAccess()

        #expect(store.locationPermissionStatus == .authorizedAlways)
        #expect(mock.requestCallCount == 1)
    }

    @Test
    @MainActor
    func requestLocationAccessSurfacesError() async {
        let mock = MockLocationPermissionService()
        mock.requestResult = .failure(LocationPermissionError.requestFailed("denied"))
        let store = AppStore(locationPermissionService: mock)

        await store.requestLocationAccess()

        #expect(store.lastError == "denied")
    }
}
```

- [ ] **Step 5: Wire ProductionABridgeAppStoreMaker + MockABridgeAppStoreMaker**

`ABridgeAppStoreMaking.swift` — create shared `LocationPermissionService()` and pass to `AppStore` and `SettingsStore`.

`MockABridgeAppStoreMaker.swift` — same wiring with `LocationPermissionService()`.

- [ ] **Step 6: Run tests + commit**

Run: `just test-swift`

```bash
git add ABridge/Models/SettingsStore.swift ABridge/Models/AppStore.swift \
        ABridge/Services/ABridgeAppStoreMaking.swift \
        ABridgeTests/SettingsStoreTests.swift ABridgeTests/MockABridgeAppStoreMaker.swift \
        ABridgeTests/AppStoreLocationTests.swift
git commit -m "feat(mapkit): wire location permission into SettingsStore and AppStore"
```

---

### Task 7: PermissionsSettingsView UI

**Files:**
- Modify: `ABridge/Views/Settings/PermissionsSettingsView.swift`

- [ ] **Step 1: Add Apple Location permission row**

After `AppleContactsPermissionRow` in the Apple Permissions section:

```swift
                AppleLocationPermissionRow(
                    required: permissionsStore.requiresAppleLocationAccess,
                    granted: appStore.locationPermissionStatus.grantsReadAccess,
                    isRequestingPermission: appStore.isRequestingLocationPermission,
                    onOpenSystemSettings: { appStore.openLocationPrivacySettings() },
                    onRequestPermissions: { Task { await appStore.requestLocationAccess() } }
                )
```

Add row view (mirror `AppleContactsPermissionRow`):

```swift
private struct AppleLocationPermissionRow: View {
    let required: Bool
    let granted: Bool
    let isRequestingPermission: Bool
    let onOpenSystemSettings: () -> Void
    let onRequestPermissions: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Location Access")
                ApplePermissionAccessStatusLabel(required: required, granted: granted)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Request Permissions", action: onRequestPermissions)
                    .buttonStyle(.borderless)
                    .disabled(granted || isRequestingPermission)

                Button(action: onOpenSystemSettings) {
                    Image(nsImage: SystemSettingsIcon.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open Location System Settings")
                .help("Open Location System Settings")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
```

- [ ] **Step 2: Add MapKitMCPPermissionsGroup**

After `ContactsMCPPermissionsGroup` in MCP Permissions section:

```swift
                MapKitMCPPermissionsGroup { capabilityID in
                    binding(for: capabilityID)
                }
```

```swift
private struct MapKitMCPPermissionsGroup: View {
    let capabilityBinding: (String) -> Binding<Bool>

    var body: some View {
        Section {
            ForEach(CapabilityCatalog.mapkitCapabilities) { capability in
                Toggle(capability.label, isOn: capabilityBinding(capability.id))
            }
        } header: {
            Text("MapKit")
        }
    }
}
```

- [ ] **Step 3: Update binding(for:) and onChange handlers**

Thread `locationAuthorized` through all `shouldApplySavedCapabilitiesAfterToggle` and `applySavedCapabilities` calls:

```swift
                let locationAuthorized = appStore.locationPermissionStatus.grantsReadAccess
```

Add `onChange` handler mirroring contacts:

```swift
        .onChange(of: appStore.locationPermissionStatus.grantsReadAccess) { _, locationAuthorized in
            guard locationAuthorized, permissionsStore.requiresAppleLocationAccess else { return }
            Task {
                await settingsStore.applySavedCapabilities(
                    remindersAuthorized: appStore.permissionStatus.grantsReadAccess,
                    eventsAuthorized: appStore.calendarPermissionStatus.grantsReadAccess,
                    contactsAuthorized: appStore.contactsPermissionStatus.grantsReadAccess,
                    locationAuthorized: true
                )
            }
        }
```

Update existing `applySavedCapabilities` / `shouldApplySavedCapabilitiesAfterToggle` calls to include `locationAuthorized`.

- [ ] **Step 4: Build + commit**

Run: `just test-swift`

```bash
git add ABridge/Views/Settings/PermissionsSettingsView.swift
git commit -m "feat(mapkit): add Location and MapKit rows to PermissionsSettingsView"
```

---

### Task 8: MapKitProvider stub + AppleProviderBridge routing

**Files:**
- Create: `ABridge/Providers/MapKit/MapKitProvider.swift`
- Modify: `ABridge/Providers/AppleProviderBridge.swift`
- Create: `ABridgeTests/AppleProviderBridgeMapKitTests.swift`

- [ ] **Step 1: Write failing bridge test**

```swift
@testable import ABridge
import Foundation
import Testing

@Suite("AppleProviderBridgeMapKit")
struct AppleProviderBridgeMapKitTests {
    @Test
    func callProviderMapKitReturnsUnknownOperation() throws {
        let bridge = AppleProviderBridge()
        let request = ProviderRequest(provider: "mapkit", operation: "search_places", payloadJson: "{}")
        let response = bridge.callProvider(request: request)
        #expect(response.ok == false)

        let errorJson = try #require(response.errorJson)
        let data = try #require(errorJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["code"] as? String == "unknown_operation")
        #expect((decoded?["message"] as? String)?.contains("search_places") == true)
    }
}
```

- [ ] **Step 2: Implement MapKitProvider stub**

```swift
import Foundation

@MainActor
enum LiveMapKitEnvironment {
    static let sharedProvider = MapKitProvider()
}

@MainActor
struct MapKitProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        let payload: [String: String] = [
            "code": "unknown_operation",
            "message": "Unknown mapkit operation: \(operation)",
        ]
        let errorJson = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? #"{"code":"unknown_operation"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
    }
}
```

- [ ] **Step 3: Add mapkit case to AppleProviderBridge**

Add factory property and init parameter:

```swift
    private let makeMapKitProvider: @MainActor @Sendable () -> MapKitProvider
```

Default: `{ LiveMapKitEnvironment.sharedProvider }`

Add test seam:

```swift
    @MainActor
    convenience init(mapKitProvider: MapKitProvider) {
        self.init(makeMapKitProvider: { [mapKitProvider] in mapKitProvider })
    }
```

Add routing case before `default`:

```swift
        case "mapkit":
            return Self.performOnMainActor { [makeMapKitProvider] in
                let provider = makeMapKitProvider()
                return provider.handle(operation: request.operation, payloadJson: request.payloadJson)
            }
```

- [ ] **Step 4: Run tests + commit**

Run: `just test-swift`

```bash
git add ABridge/Providers/MapKit/MapKitProvider.swift \
        ABridge/Providers/AppleProviderBridge.swift \
        ABridgeTests/AppleProviderBridgeMapKitTests.swift
git commit -m "feat(mapkit): add MapKitProvider stub and bridge routing"
```

---

### Task 9: Final verification

- [ ] **Step 1: Run full Swift test suite**

```bash
TZ=UTC just test-swift
```

Expected: all tests pass

- [ ] **Step 2: Run full CI (before review)**

```bash
TZ=UTC just ci
```

Expected: all checks pass

- [ ] **Step 3: Fix any failures and commit**
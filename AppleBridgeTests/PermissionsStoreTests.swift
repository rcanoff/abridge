import Foundation
import Testing
@testable import AppleBridge

@Suite("PermissionsDerivation")
struct PermissionsStoreTests {
    @Test
    func readCheckedAndSavedIsMCPActive() {
        let read = CapabilityCatalog.remindersCapabilities[0]
        let enforcement = PermissionsDerivation.computeEnforcement(
            for: read,
            checked: true,
            saved: true,
            remindersAuthorized: true
        )

        #expect(enforcement.mcp == .active)
        #expect(enforcement.apple == .granted)
    }

    @Test
    func createUnshippedIsMCPBlocked() {
        let create = CapabilityCatalog.remindersCapabilities[1]
        let enforcement = PermissionsDerivation.computeEnforcement(
            for: create,
            checked: true,
            saved: false,
            remindersAuthorized: true
        )

        #expect(enforcement.mcp == .blocked)
        #expect(enforcement.apple == .granted)
    }

    @Test
    func mcpSummaryShowsBlockedSelections() {
        let summary = PermissionsDerivation.mcpSummary(
            savedCapabilityIDs: [],
            checkedCapabilityIDs: ["create"]
        )

        #expect(summary == "Blocked: Create")
    }

    @Test
    func unshippedOnlySelectionHasNoPendingChanges() {
        let hasChanges = PermissionsDerivation.hasPendingChanges(
            checkedCapabilityIDs: ["create"],
            savedCapabilityIDs: []
        )

        #expect(hasChanges == false)
    }

    @Test
    func unshippedOnlySelectionDoesNotRequireAppleAccess() {
        #expect(PermissionsDerivation.requiresAppleAccess(for: ["create"]) == false)
        #expect(PermissionsDerivation.requiresAppleAccess(for: ["read"]) == true)
    }

    @Test
    func unshippedOnlySelectionAppleSummaryIsNone() {
        let summary = PermissionsDerivation.appleSummary(
            checkedCapabilityIDs: ["create"],
            remindersAuthorized: false
        )

        #expect(summary == "None")
    }

    @Test
    func shippedSelectionAppleSummaryShowsNeededWhenUnauthorized() {
        let summary = PermissionsDerivation.appleSummary(
            checkedCapabilityIDs: ["read"],
            remindersAuthorized: false
        )

        #expect(summary == "Reminders — needed")
    }

    @Test
    func shippedSelectionAppleSummaryShowsFullAccessWhenAuthorized() {
        let summary = PermissionsDerivation.appleSummary(
            checkedCapabilityIDs: ["read"],
            remindersAuthorized: true
        )

        #expect(summary == "Reminders — Full access")
    }

    @Test
    func hasPendingChangesWhenClearingLastSavedCapability() {
        let hasChanges = PermissionsDerivation.hasPendingChanges(
            checkedCapabilityIDs: [],
            savedCapabilityIDs: ["read"]
        )

        #expect(hasChanges == true)
    }

    @Test
    func savedIDsAfterSaveFiltersUnshipped() {
        let saved = PermissionsDerivation.savedIDsAfterSave(from: ["read", "create"])
        #expect(saved == ["read"])
    }

    @Test
    func readCapabilityShowsAppleNeededWhenWriteOnly() {
        let read = CapabilityCatalog.remindersCapabilities[0]
        let enforcement = PermissionsDerivation.computeEnforcement(
            for: read,
            checked: true,
            saved: true,
            remindersAuthorized: false
        )

        #expect(enforcement.apple == .needed)
        #expect(enforcement.mcp == .active)
    }
}

@Suite("PermissionsStore")
struct PermissionsStoreIntegrationTests {
    @Test
    @MainActor
    func writeOnlyStatusIsNotRemindersAuthorized() {
        let suiteName = "PermissionsStoreTests.writeOnly"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let mock = MockRemindersPermissionService()
        mock.status = .writeOnly
        let store = PermissionsStore(
            appSettings: AppSettings(defaults: defaults),
            permissionService: mock
        )

        #expect(store.remindersAuthorized == false)
    }

    @Test
    @MainActor
    func writeOnlyReadEnforcementShowsAppleNeeded() {
        let suiteName = "PermissionsStoreTests.writeOnlyEnforcement"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let mock = MockRemindersPermissionService()
        mock.status = .writeOnly
        let appSettings = AppSettings(defaults: defaults)
        appSettings.saveCapabilityIDs(["read"])
        let store = PermissionsStore(appSettings: appSettings, permissionService: mock)

        let read = CapabilityCatalog.remindersCapabilities[0]
        let enforcement = store.enforcement(for: read)

        #expect(enforcement.apple == .needed)
        #expect(enforcement.mcp == .active)
    }

    @Test
    @MainActor
    func saveReconcilesCheckedIDsAfterFilteringUnshipped() async {
        let suiteName = "PermissionsStoreTests.saveReconcile"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let mock = MockRemindersPermissionService()
        mock.status = .authorized
        let store = PermissionsStore(
            appSettings: AppSettings(defaults: defaults),
            permissionService: mock
        )
        store.setChecked(true, for: "read")
        store.setChecked(true, for: "create")

        let saved = await store.save()

        #expect(saved == true)
        #expect(store.checkedCapabilityIDs == ["read"])
        #expect(store.savedCapabilityIDs == ["read"])
        #expect(store.hasPendingChanges == false)
    }

    @Test
    @MainActor
    func saveRequestsAccessWhenWriteOnlyAndReadChecked() async {
        let suiteName = "PermissionsStoreTests.writeOnlySave"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let mock = MockRemindersPermissionService()
        mock.status = .writeOnly
        mock.requestResult = .success(.authorized)
        let store = PermissionsStore(
            appSettings: AppSettings(defaults: defaults),
            permissionService: mock
        )
        store.setChecked(true, for: "read")

        let saved = await store.save()

        #expect(saved == true)
        #expect(mock.requestCallCount == 1)
    }
}
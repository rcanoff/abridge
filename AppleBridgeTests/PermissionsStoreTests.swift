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
}
@testable import ABridge
import Testing

/// Ensures Settings capability IDs are driven by the Rust-owned catalog export.
@Suite("CapabilityCatalog source of truth")
struct CapabilityCatalogSourceOfTruthTests {
    @Test
    func catalogMatchesRustExport() {
        let fromRust = listSettingsCapabilities()
        let fromSwift =
            CapabilityCatalog.remindersCapabilities
                + CapabilityCatalog.calendarsCapabilities
                + CapabilityCatalog.eventsCapabilities
                + CapabilityCatalog.contactsCapabilities
                + CapabilityCatalog.mapkitCapabilities
                + CapabilityCatalog.corelocationCapabilities
                + CapabilityCatalog.visionCapabilities

        #expect(fromSwift.count == fromRust.count)
        #expect(fromSwift.count == 35)

        let swiftIDs = Set(fromSwift.map(\.capabilityID))
        let rustIDs = Set(fromRust.map(\.capabilityId))
        #expect(swiftIDs == rustIDs)

        for entry in fromRust {
            let mapped = fromSwift.first { $0.capabilityID == entry.capabilityId }
            #expect(mapped != nil)
            #expect(mapped?.id == entry.id)
            #expect(mapped?.label == entry.label)
            #expect(mapped?.shipped == entry.shipped)
        }
    }

    @Test
    func remindersReadComesFromRust() {
        let rust = listSettingsCapabilities().first { $0.capabilityId == "eventkit.reminders.read" }
        let swift = CapabilityCatalog.remindersCapabilities.first { $0.capabilityID == "eventkit.reminders.read" }
        #expect(rust != nil)
        #expect(swift != nil)
        #expect(swift?.label == rust?.label)
        #expect(swift?.shipped == true)
    }
}

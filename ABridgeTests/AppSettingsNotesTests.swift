@testable import ABridge
import Foundation
import Testing

@Suite("AppSettingsNotes")
struct AppSettingsNotesTests {
    @Test
    @MainActor
    func serverEnabledMCPCapabilityIDsFollowsNotesGate() throws {
        let suiteName = "AppSettingsNotesTests.notesServerGating"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let appSettings = AppSettings(defaults: defaults)
        let notesIDs = Set(CapabilityCatalog.notesCapabilities.map(\.id))
        appSettings.saveCapabilityIDs(notesIDs)

        let enabled = appSettings.enabledNotesCapabilityIDs
        #expect(enabled == CapabilityCatalog.notesCapabilities.filter(\.shipped).map(\.capabilityID))

        #expect(notesSent(by: appSettings, fullDiskAccessGranted: false, automationDenied: false).isEmpty)
        #expect(
            notesSent(by: appSettings, fullDiskAccessGranted: true, automationDenied: true)
                == NotesCapabilityGate.serverCapabilityIDs(
                    enabled: enabled,
                    fullDiskAccessGranted: true,
                    automationDenied: true
                )
        )
        #expect(
            notesSent(by: appSettings, fullDiskAccessGranted: true, automationDenied: false)
                == NotesCapabilityGate.serverCapabilityIDs(
                    enabled: enabled,
                    fullDiskAccessGranted: true,
                    automationDenied: false
                )
        )
    }

    @MainActor
    private func notesSent(
        by appSettings: AppSettings,
        fullDiskAccessGranted: Bool,
        automationDenied: Bool
    ) -> [String] {
        appSettings.serverEnabledMCPCapabilityIDs(
            remindersAuthorized: false,
            eventsAuthorized: false,
            contactsAuthorized: false,
            locationAuthorized: false,
            notesFullDiskAccessGranted: fullDiskAccessGranted,
            notesAutomationDenied: automationDenied
        ).filter { $0.hasPrefix("notes.") }
    }
}

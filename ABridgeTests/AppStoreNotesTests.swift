@testable import ABridge
import Foundation
import Testing

@Suite("AppStoreNotes")
struct AppStoreNotesTests {
    @Test
    @MainActor
    func requestNotesAutomationAccessUpdatesStatus() async {
        let automation = MockNotesAutomationService()
        automation.status = .notDetermined
        automation.requestResult = .success(.granted)
        let store = AppStore(notesAutomationService: automation)

        await store.requestNotesAutomationAccess()

        #expect(store.notesAutomationStatus == .granted)
        #expect(automation.requestCallCount == 1)
        #expect(store.lastError == nil)
        #expect(store.isRequestingNotesAutomation == false)
    }

    @Test
    @MainActor
    func requestNotesAutomationAccessSurfacesLaunchError() async {
        let automation = MockNotesAutomationService()
        automation.requestResult = .failure(NotesAutomationRequestFailure(message: "Notes did not launch"))
        let store = AppStore(
            notesFullDiskAccessService: MockNotesFullDiskAccessService(),
            notesAutomationService: automation
        )

        await store.requestNotesAutomationAccess()

        #expect(store.lastError == "Notes did not launch")
        #expect(store.isRequestingNotesAutomation == false)
    }

    @Test
    @MainActor
    func openFullDiskAccessSettingsUsesPrivacyAllFiles() {
        let urlOpener = MockURLOpener()
        let store = AppStore(urlOpener: urlOpener)

        store.openFullDiskAccessSettings()

        #expect(
            urlOpener.openedURL?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
        #expect(store.lastError == nil)
    }

    @Test
    @MainActor
    func openAutomationPrivacySettingsUsesPrivacyAutomation() {
        let urlOpener = MockURLOpener()
        let store = AppStore(urlOpener: urlOpener)

        store.openAutomationPrivacySettings()

        #expect(
            urlOpener.openedURL?.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        )
        #expect(store.lastError == nil)
    }

    @Test
    @MainActor
    func openFullDiskAccessSettingsSetsErrorOnFailure() {
        let urlOpener = MockURLOpener()
        urlOpener.shouldSucceed = false
        let store = AppStore(urlOpener: urlOpener)

        store.openFullDiskAccessSettings()

        #expect(store.lastError == "Unable to open Full Disk Access settings.")
    }
}

private struct NotesAutomationRequestFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

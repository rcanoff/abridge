import Foundation
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
        let mock = BlockingRemindersPermissionService()
        let store = AppStore(permissionService: mock)

        let task = Task { await store.requestAccess() }
        await Task.yield()

        #expect(store.isRequestingPermission == true)

        mock.resume(with: .success(.authorized))
        await task.value

        #expect(store.isRequestingPermission == false)
    }

    @Test
    @MainActor
    func openRemindersPrivacySettingsClearsErrorOnSuccess() {
        let urlOpener = MockURLOpener()
        urlOpener.shouldSucceed = true
        let store = AppStore(urlOpener: urlOpener)

        store.openRemindersPrivacySettings()

        #expect(store.lastError == nil)
        #expect(urlOpener.openedURL != nil)
    }

    @Test
    @MainActor
    func openRemindersPrivacySettingsSetsErrorOnFailure() {
        let urlOpener = MockURLOpener()
        urlOpener.shouldSucceed = false
        let store = AppStore(urlOpener: urlOpener)

        store.openRemindersPrivacySettings()

        #expect(store.lastError == "Unable to open Reminders privacy settings.")
    }
}
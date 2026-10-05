@testable import ABridge
import Contacts
import Testing

@Suite("ContactsPermissionService")
struct ContactsPermissionServiceTests {
    @Test
    @MainActor
    func currentStatusMapsAuthorizationStatus() {
        let service = ContactsPermissionService(
            authorizationStatusProvider: { .authorized }
        )
        #expect(service.currentStatus() == .authorized)
    }

    @Test
    @MainActor
    func requestAccessReturnsHandlerResult() async throws {
        let service = ContactsPermissionService(
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
        let service = ContactsPermissionService(
            requestAccessHandler: { throw ContactsPermissionError.requestFailed("denied") }
        )
        await #expect(throws: ContactsPermissionError.self) {
            _ = try await service.requestAccess()
        }
    }
}

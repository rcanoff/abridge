@testable import ABridge
import Contacts
import Testing

@Suite("ContactsPermissionStatus")
struct ContactsPermissionStatusTests {
    @Test
    func mapNotDetermined() {
        #expect(ContactsPermissionStatusMapper.map(.notDetermined) == .notDetermined)
    }

    @Test
    func mapAuthorizedGrantsReadAccess() {
        let status = ContactsPermissionStatusMapper.map(.authorized)
        #expect(status == .authorized)
        #expect(status.grantsReadAccess)
    }

    @Test
    func mapDeniedDoesNotGrantReadAccess() {
        let status = ContactsPermissionStatusMapper.map(.denied)
        #expect(status.grantsReadAccess == false)
    }

    @Test
    func mapLimitedGrantsReadAccess() throws {
        // CNAuthorizationStatus.limited is iOS-only in the SDK; raw value 4 exercises the mapper on macOS CI.
        let limitedStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let status = ContactsPermissionStatusMapper.map(limitedStatus)
        #expect(status == .limited)
        #expect(status.grantsReadAccess)
    }

    @Test
    func mapAuthorizedGrantsWriteAccess() {
        let status = ContactsPermissionStatusMapper.map(.authorized)
        #expect(status.grantsWriteAccess)
    }

    @Test
    func mapLimitedDoesNotGrantWriteAccess() throws {
        let limitedStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let status = ContactsPermissionStatusMapper.map(limitedStatus)
        #expect(status.grantsWriteAccess == false)
    }

    @Test
    func mapDeniedDoesNotGrantWriteAccess() {
        let status = ContactsPermissionStatusMapper.map(.denied)
        #expect(status.grantsWriteAccess == false)
    }
}

@testable import AppleBridge
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
}

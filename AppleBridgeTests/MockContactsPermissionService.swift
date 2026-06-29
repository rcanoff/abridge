@testable import AppleBridge
import Foundation

@MainActor
final class MockContactsPermissionService: ContactsPermissionChecking {
    var status: ContactsPermissionStatus = .notDetermined
    var requestResult: Result<ContactsPermissionStatus, Error> = .success(.authorized)
    private(set) var requestCallCount = 0

    func currentStatus() -> ContactsPermissionStatus {
        status
    }

    func requestAccess() async throws -> ContactsPermissionStatus {
        requestCallCount += 1
        let result = try requestResult.get()
        status = result
        return result
    }
}

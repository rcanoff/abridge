import Foundation
@testable import AppleBridge

final class MockRemindersPermissionService: RemindersPermissionChecking, @unchecked Sendable {
    var status: RemindersPermissionStatus = .notDetermined
    var requestResult: Result<RemindersPermissionStatus, Error> = .success(.authorized)
    private(set) var requestCallCount = 0

    func currentStatus() -> RemindersPermissionStatus {
        status
    }

    func requestAccess() async throws -> RemindersPermissionStatus {
        requestCallCount += 1
        return try requestResult.get()
    }
}
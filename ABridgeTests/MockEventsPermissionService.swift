@testable import ABridge
import Foundation

@MainActor
final class MockEventsPermissionService: EventsPermissionChecking {
    var status: EventsPermissionStatus = .notDetermined
    var requestResult: Result<EventsPermissionStatus, Error> = .success(.authorized)
    private(set) var requestCallCount = 0

    func currentStatus() -> EventsPermissionStatus {
        status
    }

    func requestAccess() async throws -> EventsPermissionStatus {
        requestCallCount += 1
        return try requestResult.get()
    }
}

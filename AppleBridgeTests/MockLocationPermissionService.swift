@testable import AppleBridge
import Foundation

@MainActor
final class MockLocationPermissionService: LocationPermissionChecking {
    var status: LocationPermissionStatus = .notDetermined
    var requestResult: Result<LocationPermissionStatus, Error> = .success(.authorized)
    private(set) var requestCallCount = 0

    func currentStatus() -> LocationPermissionStatus {
        status
    }

    func requestAccess() async throws -> LocationPermissionStatus {
        requestCallCount += 1
        let result = try requestResult.get()
        status = result
        return result
    }
}
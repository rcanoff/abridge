@testable import AppleBridge
import Foundation

@MainActor
final class BlockingLocationPermissionService: LocationPermissionChecking {
    var status: LocationPermissionStatus = .notDetermined
    private var continuation: CheckedContinuation<LocationPermissionStatus, Error>?

    func currentStatus() -> LocationPermissionStatus {
        status
    }

    func requestAccess() async throws -> LocationPermissionStatus {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: Result<LocationPermissionStatus, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
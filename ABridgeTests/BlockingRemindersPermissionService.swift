@testable import ABridge
import Foundation

@MainActor
final class BlockingRemindersPermissionService: RemindersPermissionChecking {
    var status: RemindersPermissionStatus = .notDetermined
    private var continuation: CheckedContinuation<RemindersPermissionStatus, Error>?

    func currentStatus() -> RemindersPermissionStatus {
        status
    }

    func requestAccess() async throws -> RemindersPermissionStatus {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: Result<RemindersPermissionStatus, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

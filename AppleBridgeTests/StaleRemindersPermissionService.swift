@testable import AppleBridge
import Foundation

/// Simulates EventKit returning a stale `notDetermined` status after `requestFullAccessToReminders` granted.
@MainActor
final class StaleRemindersPermissionService: RemindersPermissionChecking {
    private var state = RemindersPermissionStatusReconciliation.State(sessionGrantConfirmed: false)

    func currentStatus() -> RemindersPermissionStatus {
        let resolved = RemindersPermissionStatusReconciliation.resolve(
            eventKitStatus: .notDetermined,
            state: state
        )
        state = resolved.state
        return resolved.status
    }

    func requestAccess() async throws -> RemindersPermissionStatus {
        state = RemindersPermissionStatusReconciliation.afterRequest(
            result: .authorized,
            state: state
        )
        return .authorized
    }
}

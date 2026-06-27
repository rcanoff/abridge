import EventKit
import Foundation

enum RemindersPermissionError: LocalizedError, Equatable {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return message
        }
    }
}

final class RemindersPermissionService: RemindersPermissionChecking, @unchecked Sendable {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func currentStatus() -> RemindersPermissionStatus {
        let ekStatus = EKEventStore.authorizationStatus(for: .reminder)
        return RemindersPermissionStatusMapper.map(ekStatus)
    }

    func requestAccess() async throws -> RemindersPermissionStatus {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    continuation.resume(
                        throwing: RemindersPermissionError.requestFailed(error.localizedDescription)
                    )
                    return
                }

                if granted {
                    continuation.resume(returning: .authorized)
                } else {
                    continuation.resume(returning: .denied)
                }
            }
        }
    }
}
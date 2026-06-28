import EventKit
import Foundation

enum RemindersPermissionError: LocalizedError, Equatable {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(message):
            message
        }
    }
}

@MainActor
final class RemindersPermissionService: RemindersPermissionChecking {
    typealias AuthorizationStatusProvider = @MainActor () -> EKAuthorizationStatus
    typealias RequestAccessHandler = @MainActor () async throws -> RemindersPermissionStatus

    private let eventStore: EKEventStore
    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let requestAccessHandler: RequestAccessHandler
    private var reconciliationState: RemindersPermissionStatusReconciliation.State
    private nonisolated(unsafe) var eventStoreObserver: NSObjectProtocol?

    init(
        eventStore: EKEventStore = EKEventStore(),
        authorizationStatusProvider: AuthorizationStatusProvider? = nil,
        requestAccessHandler: RequestAccessHandler? = nil
    ) {
        self.eventStore = eventStore
        self.authorizationStatusProvider = authorizationStatusProvider ?? {
            EKEventStore.authorizationStatus(for: .reminder)
        }
        self.requestAccessHandler = requestAccessHandler ?? { [eventStore] in
            try await Self.requestFullAccess(using: eventStore)
        }

        let initialStatus = RemindersPermissionStatusMapper.map(self.authorizationStatusProvider())
        reconciliationState = RemindersPermissionStatusReconciliation.initialState(for: initialStatus)

        eventStoreObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncReconciliationFromEventKit()
            }
        }
    }

    deinit {
        if let eventStoreObserver {
            NotificationCenter.default.removeObserver(eventStoreObserver)
        }
    }

    func currentStatus() -> RemindersPermissionStatus {
        resolveStatus(from: authorizationStatusProvider())
    }

    func requestAccess() async throws -> RemindersPermissionStatus {
        let result = try await requestAccessHandler()
        reconciliationState = RemindersPermissionStatusReconciliation.afterRequest(
            result: result,
            state: reconciliationState
        )
        return result
    }

    private func syncReconciliationFromEventKit() {
        _ = resolveStatus(from: authorizationStatusProvider())
    }

    private func resolveStatus(from ekStatus: EKAuthorizationStatus) -> RemindersPermissionStatus {
        let mapped = RemindersPermissionStatusMapper.map(ekStatus)
        let resolved = RemindersPermissionStatusReconciliation.resolve(
            eventKitStatus: mapped,
            state: reconciliationState
        )
        reconciliationState = resolved.state
        return resolved.status
    }

    private static func requestFullAccess(using eventStore: EKEventStore) async throws -> RemindersPermissionStatus {
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

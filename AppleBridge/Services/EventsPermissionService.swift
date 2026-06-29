import EventKit
import Foundation

enum EventsPermissionError: LocalizedError, Equatable {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case let .requestFailed(message):
            message
        }
    }
}

@MainActor
final class EventsPermissionService: EventsPermissionChecking {
    typealias AuthorizationStatusProvider = @MainActor () -> EKAuthorizationStatus
    typealias RequestAccessHandler = @MainActor () async throws -> EventsPermissionStatus

    private let eventStore: EKEventStore
    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let requestAccessHandler: RequestAccessHandler
    private var reconciliationState: EventsPermissionStatusReconciliation.State
    private nonisolated(unsafe) var eventStoreObserver: NSObjectProtocol?

    init(
        eventStore: EKEventStore = EKEventStore(),
        authorizationStatusProvider: AuthorizationStatusProvider? = nil,
        requestAccessHandler: RequestAccessHandler? = nil
    ) {
        self.eventStore = eventStore
        self.authorizationStatusProvider = authorizationStatusProvider ?? {
            EKEventStore.authorizationStatus(for: .event)
        }
        self.requestAccessHandler = requestAccessHandler ?? { [eventStore] in
            try await Self.requestFullAccess(using: eventStore)
        }

        let initialStatus = EventsPermissionStatusMapper.map(self.authorizationStatusProvider())
        reconciliationState = EventsPermissionStatusReconciliation.initialState(for: initialStatus)

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

    func currentStatus() -> EventsPermissionStatus {
        resolveStatus(from: authorizationStatusProvider())
    }

    func requestAccess() async throws -> EventsPermissionStatus {
        let result = try await requestAccessHandler()
        reconciliationState = EventsPermissionStatusReconciliation.afterRequest(
            result: result,
            state: reconciliationState
        )
        return result
    }

    private func syncReconciliationFromEventKit() {
        _ = resolveStatus(from: authorizationStatusProvider())
    }

    private func resolveStatus(from ekStatus: EKAuthorizationStatus) -> EventsPermissionStatus {
        let mapped = EventsPermissionStatusMapper.map(ekStatus)
        let resolved = EventsPermissionStatusReconciliation.resolve(
            eventKitStatus: mapped,
            state: reconciliationState
        )
        reconciliationState = resolved.state
        return resolved.status
    }

    private static func requestFullAccess(using eventStore: EKEventStore) async throws -> EventsPermissionStatus {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(
                        throwing: EventsPermissionError.requestFailed(error.localizedDescription)
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
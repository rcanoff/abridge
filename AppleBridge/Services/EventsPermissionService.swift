import EventKit
import Foundation

@MainActor
final class EventsPermissionService: EventsPermissionChecking {
    typealias AuthorizationStatusProvider = @MainActor () -> EKAuthorizationStatus

    private let authorizationStatusProvider: AuthorizationStatusProvider

    init(authorizationStatusProvider: AuthorizationStatusProvider? = nil) {
        self.authorizationStatusProvider = authorizationStatusProvider ?? {
            EKEventStore.authorizationStatus(for: .event)
        }
    }

    func grantsReadAccess() -> Bool {
        authorizationStatusProvider() == .fullAccess
    }
}

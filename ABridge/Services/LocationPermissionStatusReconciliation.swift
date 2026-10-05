import Foundation

enum LocationPermissionStatusReconciliation {
    struct State: Equatable {
        var sessionGrantConfirmed: Bool
    }

    static func resolve(
        systemStatus: LocationPermissionStatus,
        state: State
    ) -> (status: LocationPermissionStatus, state: State) {
        if systemStatus.grantsReadAccess {
            return (systemStatus, State(sessionGrantConfirmed: true))
        }

        switch systemStatus {
        case .denied, .restricted:
            return (systemStatus, State(sessionGrantConfirmed: false))
        default:
            // Sticky grant across flaky CoreLocation `.notDetermined` / `.unknown` reads
            // after a confirmed in-session grant (same pattern as EventKit reconciliation).
            if state.sessionGrantConfirmed {
                return (.authorized, state)
            }
            return (systemStatus, state)
        }
    }

    static func afterRequest(result: LocationPermissionStatus, state _: State) -> State {
        State(sessionGrantConfirmed: result.grantsReadAccess)
    }

    static func initialState(for systemStatus: LocationPermissionStatus) -> State {
        State(sessionGrantConfirmed: systemStatus.grantsReadAccess)
    }
}

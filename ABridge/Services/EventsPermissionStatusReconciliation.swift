import Foundation

enum EventsPermissionStatusReconciliation {
    struct State: Equatable {
        var sessionGrantConfirmed: Bool
    }

    static func resolve(
        eventKitStatus: EventsPermissionStatus,
        state: State
    ) -> (status: EventsPermissionStatus, state: State) {
        if eventKitStatus.grantsReadAccess {
            return (eventKitStatus, State(sessionGrantConfirmed: true))
        }

        switch eventKitStatus {
        case .denied, .restricted, .writeOnly:
            return (eventKitStatus, State(sessionGrantConfirmed: false))
        default:
            if state.sessionGrantConfirmed {
                return (.authorized, state)
            }
            return (eventKitStatus, state)
        }
    }

    static func afterRequest(result: EventsPermissionStatus, state _: State) -> State {
        State(sessionGrantConfirmed: result.grantsReadAccess)
    }

    static func initialState(for eventKitStatus: EventsPermissionStatus) -> State {
        State(sessionGrantConfirmed: eventKitStatus.grantsReadAccess)
    }
}

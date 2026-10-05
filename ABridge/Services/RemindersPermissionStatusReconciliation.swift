import Foundation

enum RemindersPermissionStatusReconciliation {
    struct State: Equatable {
        var sessionGrantConfirmed: Bool
    }

    static func resolve(
        eventKitStatus: RemindersPermissionStatus,
        state: State
    ) -> (status: RemindersPermissionStatus, state: State) {
        if eventKitStatus.grantsReadAccess {
            return (eventKitStatus, State(sessionGrantConfirmed: true))
        }

        switch eventKitStatus {
        case .denied, .restricted:
            return (eventKitStatus, State(sessionGrantConfirmed: false))
        default:
            if state.sessionGrantConfirmed {
                return (.authorized, state)
            }
            return (eventKitStatus, state)
        }
    }

    static func afterRequest(result: RemindersPermissionStatus, state _: State) -> State {
        State(sessionGrantConfirmed: result.grantsReadAccess)
    }

    static func initialState(for eventKitStatus: RemindersPermissionStatus) -> State {
        State(sessionGrantConfirmed: eventKitStatus.grantsReadAccess)
    }
}

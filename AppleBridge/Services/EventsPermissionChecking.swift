import Foundation

@MainActor
protocol EventsPermissionChecking {
    func grantsReadAccess() -> Bool
}

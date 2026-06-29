import Foundation

@MainActor
protocol EventsPermissionChecking {
    func currentStatus() -> EventsPermissionStatus
    func requestAccess() async throws -> EventsPermissionStatus
}
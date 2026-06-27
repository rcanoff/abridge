import Foundation

@MainActor
protocol RemindersPermissionChecking {
    func currentStatus() -> RemindersPermissionStatus
    func requestAccess() async throws -> RemindersPermissionStatus
}
import Foundation

@MainActor
protocol ContactsPermissionChecking {
    func currentStatus() -> ContactsPermissionStatus
    func requestAccess() async throws -> ContactsPermissionStatus
}

import Foundation

protocol RemindersPermissionChecking: Sendable {
    func currentStatus() -> RemindersPermissionStatus
    func requestAccess() async throws -> RemindersPermissionStatus
}
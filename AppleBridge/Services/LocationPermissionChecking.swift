import Foundation

@MainActor
protocol LocationPermissionChecking {
    func currentStatus() -> LocationPermissionStatus
    func requestAccess() async throws -> LocationPermissionStatus
}
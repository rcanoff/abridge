import Foundation
import Observation

@Observable
@MainActor
final class AppStore {
    private(set) var permissionStatus: RemindersPermissionStatus = .unknown
    private(set) var isRequestingPermission = false
    private(set) var lastError: String?

    private let permissionService: any RemindersPermissionChecking

    init(permissionService: any RemindersPermissionChecking = RemindersPermissionService()) {
        self.permissionService = permissionService
    }

    func refreshStatus() {
        lastError = nil
        permissionStatus = permissionService.currentStatus()
    }

    func requestAccess() async {
        guard !isRequestingPermission else { return }

        isRequestingPermission = true
        lastError = nil

        defer { isRequestingPermission = false }

        do {
            permissionStatus = try await permissionService.requestAccess()
        } catch {
            refreshStatus()
            lastError = error.localizedDescription
        }
    }
}
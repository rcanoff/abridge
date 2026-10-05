import Foundation
import ServiceManagement

@MainActor
final class SMAppLaunchAtLoginService: LaunchAtLoginManaging {
    var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func register() throws {
        do {
            try SMAppService.mainApp.register()
        } catch {
            throw LaunchAtLoginError.registrationFailed
        }
    }

    func unregister() throws {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            throw LaunchAtLoginError.unregistrationFailed
        }
    }
}

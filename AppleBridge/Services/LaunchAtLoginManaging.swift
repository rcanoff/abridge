import Foundation

enum LaunchAtLoginError: LocalizedError {
    case registrationFailed
    case unregistrationFailed

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            "Could not enable launch at login. Try again or check System Settings."
        case .unregistrationFailed:
            "Could not disable launch at login. Try again or check System Settings."
        }
    }
}

@MainActor
protocol LaunchAtLoginManaging {
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

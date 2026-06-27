import Foundation

enum ServerRunState: Equatable, Sendable {
    case stopped
    case starting
    case running
    case error(String)

    var displayName: String {
        switch self {
        case .stopped:
            return "Stopped"
        case .starting:
            return "Starting…"
        case .running:
            return "Running"
        case .error:
            return "Error"
        }
    }
}
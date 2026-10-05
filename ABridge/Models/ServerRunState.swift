import Foundation

enum ServerRunState: Equatable {
    case stopped
    case starting
    case running
    case error(String)

    var displayName: String {
        switch self {
        case .stopped:
            "Stopped"
        case .starting:
            "Starting…"
        case .running:
            "Running"
        case .error:
            "Error"
        }
    }
}

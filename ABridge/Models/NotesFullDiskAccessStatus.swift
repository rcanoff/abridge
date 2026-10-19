import Foundation

enum NotesFullDiskAccessStatus: Equatable {
    case granted
    case notGranted
    case notSetUp
    case unknown

    var grantsAccess: Bool {
        self == .granted
    }

    var displayName: String {
        switch self {
        case .granted:
            "Granted"
        case .notGranted:
            "Not granted"
        case .notSetUp:
            "Notes not set up"
        case .unknown:
            "Unknown"
        }
    }
}

enum NotesStoreProbeOutcome: Equatable, Sendable {
    case opened
    case posixError(Int32)
}

enum NotesFullDiskAccessStatusMapper {
    static func map(_ outcome: NotesStoreProbeOutcome) -> NotesFullDiskAccessStatus {
        switch outcome {
        case .opened:
            .granted
        case let .posixError(code) where code == ENOENT:
            .notSetUp
        case let .posixError(code) where code == EPERM || code == EACCES:
            .notGranted
        case .posixError:
            .unknown
        }
    }
}

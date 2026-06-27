import EventKit
import Foundation

enum RemindersPermissionStatus: Equatable, CaseIterable, Sendable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case restricted

    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .notDetermined:
            return "Not Determined"
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }
}

enum RemindersPermissionStatusMapper {
    static func map(_ status: EKAuthorizationStatus) -> RemindersPermissionStatus {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .writeOnly:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }
}
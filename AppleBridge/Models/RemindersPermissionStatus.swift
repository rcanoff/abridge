import EventKit
import Foundation

enum RemindersPermissionStatus: Equatable, CaseIterable {
    case unknown
    case notDetermined
    case authorized
    case denied
    case restricted

    var displayName: String {
        switch self {
        case .unknown:
            "Unknown"
        case .notDetermined:
            "Not Determined"
        case .authorized:
            "Authorized"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
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

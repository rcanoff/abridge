import EventKit
import Foundation

enum RemindersPermissionStatus: Equatable, CaseIterable {
    case unknown
    case notDetermined
    case authorized
    case writeOnly
    case denied
    case restricted

    var grantsReadAccess: Bool {
        self == .authorized
    }

    var displayName: String {
        switch self {
        case .unknown:
            "Unknown"
        case .notDetermined:
            "Not Determined"
        case .authorized:
            "Authorized"
        case .writeOnly:
            "Write Only"
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
        case .fullAccess:
            return .authorized
        case .writeOnly:
            return .writeOnly
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }
}

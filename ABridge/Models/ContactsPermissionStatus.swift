import Contacts
import Foundation

enum ContactsPermissionStatus: Equatable, CaseIterable {
    case unknown
    case notDetermined
    case authorized
    case limited
    case denied
    case restricted

    var grantsReadAccess: Bool {
        switch self {
        case .authorized, .limited:
            true
        default:
            false
        }
    }

    var grantsWriteAccess: Bool {
        switch self {
        case .authorized:
            true
        default:
            false
        }
    }

    var displayName: String {
        switch self {
        case .unknown:
            "Unknown"
        case .notDetermined:
            "Not Determined"
        case .authorized:
            "Authorized"
        case .limited:
            "Limited"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        }
    }
}

enum ContactsPermissionStatusMapper {
    static func map(_ status: CNAuthorizationStatus) -> ContactsPermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .limited:
            .limited
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unknown
        }
    }
}

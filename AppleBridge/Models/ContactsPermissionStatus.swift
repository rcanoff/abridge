import Contacts
import Foundation

enum ContactsPermissionStatus: Equatable, CaseIterable {
    case unknown
    case notDetermined
    case authorized
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
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .unknown
        }
    }
}

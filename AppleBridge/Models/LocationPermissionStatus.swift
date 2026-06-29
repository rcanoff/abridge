import CoreLocation
import Foundation

enum LocationPermissionStatus: Equatable, CaseIterable {
    case unknown
    case notDetermined
    case authorized
    case authorizedAlways
    case denied
    case restricted

    var grantsReadAccess: Bool {
        switch self {
        case .authorized, .authorizedAlways:
            true
        default:
            false
        }
    }

    var displayName: String {
        switch self {
        case .unknown: "Unknown"
        case .notDetermined: "Not Determined"
        case .authorized: "Authorized"
        case .authorizedAlways: "Authorized Always"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }
}

enum LocationPermissionStatusMapper {
    static func map(_ status: CLAuthorizationStatus) -> LocationPermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized, .authorizedAlways: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }
}

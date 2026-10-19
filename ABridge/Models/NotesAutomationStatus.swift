import CoreServices
import Foundation

enum NotesAutomationStatus: Equatable {
    case granted
    case denied
    case notDetermined
    case unknown

    var isDenied: Bool {
        self == .denied
    }

    var displayName: String {
        switch self {
        case .granted:
            "Granted"
        case .denied:
            "Denied"
        case .notDetermined:
            "Not determined"
        case .unknown:
            "Notes not running"
        }
    }
}

enum NotesAutomationStatusMapper {
    static func map(_ status: OSStatus) -> NotesAutomationStatus {
        switch status {
        case noErr:
            .granted
        case OSStatus(errAEEventNotPermitted):
            .denied
        case OSStatus(errAEEventWouldRequireUserConsent):
            .notDetermined
        case OSStatus(procNotFound):
            .unknown
        default:
            .unknown
        }
    }
}

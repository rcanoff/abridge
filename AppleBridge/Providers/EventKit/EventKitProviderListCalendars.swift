@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func listCalendars() -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let calendars = store.eventCalendars().map(EventKitSerialization.calendarJSONObject)
            let payload = try EventKitSerialization.jsonString(from: calendars)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch {
            return providerError(from: error)
        }
    }

    var isEventAuthorized: Bool {
        switch store.eventAuthorizationStatus() {
        case .fullAccess:
            true
        default:
            false
        }
    }
}

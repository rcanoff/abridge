@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    func serializedEventJSONObject(from event: EKEvent) -> [String: Any] {
        var payload = EventKitSerialization.eventJSONObject(from: event)
        if let eventIdentifier = store.eventIdentifier(for: event) {
            payload["event_identifier"] = eventIdentifier
        } else {
            payload["event_identifier"] = NSNull()
        }
        return payload
    }
}

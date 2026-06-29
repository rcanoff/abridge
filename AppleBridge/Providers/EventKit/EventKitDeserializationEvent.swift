@preconcurrency import EventKit
import Foundation

extension EventKitDeserialization {
    static func eventAvailability(from value: Any?) throws -> EKEventAvailability? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let string = value as? String else {
            throw EventKitProviderError.invalidArguments("availability must be a string or null")
        }

        switch string {
        case "not_supported": return .notSupported
        case "busy": return .busy
        case "free": return .free
        case "tentative": return .tentative
        case "unavailable": return .unavailable
        default:
            throw EventKitProviderError.invalidArguments("Invalid availability: \(string)")
        }
    }

    static func structuredLocation(from value: Any?) throws -> EKStructuredLocation? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let dictionary = value as? [String: Any] else {
            throw EventKitProviderError.invalidArguments("structured_location must be an object or null")
        }
        return try structuredLocationFromDictionary(from: dictionary)
    }
}

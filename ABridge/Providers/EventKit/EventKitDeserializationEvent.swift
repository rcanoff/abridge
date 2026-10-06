@preconcurrency import EventKit
import Foundation

extension EventKitDeserialization {
    static func eventAvailability(from value: Any?) throws -> EKEventAvailability? {
        guard let value else { return nil }
        if value is NSNull {
            return nil
        }
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
        if value is NSNull {
            return nil
        }
        guard let dictionary = value as? [String: Any] else {
            throw EventKitProviderError.invalidArguments("structured_location must be an object or null")
        }
        return try structuredLocationFromDictionary(from: dictionary)
    }

    static func optionalPresentEventAvailability(
        _ dictionary: [String: Any],
        key: String
    ) throws -> OptionalField<EKEventAvailability> {
        guard dictionary.keys.contains(key) else { return .absent }
        return try .present(eventAvailability(from: dictionary[key]))
    }

    static func optionalPresentStructuredLocation(
        _ dictionary: [String: Any],
        key: String
    ) throws -> OptionalField<EKStructuredLocation> {
        guard dictionary.keys.contains(key) else { return .absent }
        return try .present(structuredLocation(from: dictionary[key]))
    }
}

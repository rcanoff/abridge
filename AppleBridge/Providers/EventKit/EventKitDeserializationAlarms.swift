@preconcurrency import CoreLocation
@preconcurrency import EventKit
import Foundation

extension EventKitDeserialization {
    static func alarms(from value: Any?) throws -> [EKAlarm]? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let array = value as? [Any] else {
            throw EventKitProviderError.invalidArguments("alarms must be an array or null")
        }
        return try array.map { element in
            guard let dictionary = element as? [String: Any] else {
                throw EventKitProviderError.invalidArguments("alarm entries must be objects")
            }
            return try alarm(from: dictionary)
        }
    }

    private static func alarm(from dictionary: [String: Any]) throws -> EKAlarm {
        let absoluteDate = try optionalISO8601Date(dictionary["absolute_date"])
        let relativeOffset = dictionary["relative_offset"] as? Double ?? 0

        let alarm = if let absoluteDate {
            EKAlarm(absoluteDate: absoluteDate)
        } else {
            EKAlarm(relativeOffset: relativeOffset)
        }

        if let proximity = try optionalString(dictionary["proximity"]) {
            alarm.proximity = try alarmProximity(from: proximity)
        }
        if let emailAddress = try optionalString(dictionary["email_address"]) {
            alarm.emailAddress = emailAddress
        }
        if let structuredLocationValue = dictionary["structured_location"] {
            if structuredLocationValue is NSNull {
                alarm.structuredLocation = nil
            } else if let locationDictionary = structuredLocationValue as? [String: Any] {
                alarm.structuredLocation = try structuredLocation(from: locationDictionary)
            } else {
                throw EventKitProviderError.invalidArguments("structured_location must be an object or null")
            }
        }

        return alarm
    }

    private static func structuredLocation(from dictionary: [String: Any]) throws -> EKStructuredLocation {
        let title = try optionalString(dictionary["title"]) ?? ""
        let location = EKStructuredLocation(title: title)
        if let radius = dictionary["radius"] as? Double {
            location.radius = radius
        } else if let radius = dictionary["radius"] as? NSNumber {
            location.radius = radius.doubleValue
        }

        if let geoValue = dictionary["geo_location"] {
            if geoValue is NSNull {
                location.geoLocation = nil
            } else if let geoDictionary = geoValue as? [String: Any],
                      let latitude = geoDictionary["latitude"] as? Double,
                      let longitude = geoDictionary["longitude"] as? Double
            {
                location.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
            } else {
                throw EventKitProviderError
                    .invalidArguments("geo_location must be an object with latitude and longitude")
            }
        }

        return location
    }

    private static func alarmProximity(from string: String) throws -> EKAlarmProximity {
        switch string {
        case "none": .none
        case "enter": .enter
        case "leave": .leave
        default:
            throw EventKitProviderError.invalidArguments("Invalid alarm proximity: \(string)")
        }
    }
}

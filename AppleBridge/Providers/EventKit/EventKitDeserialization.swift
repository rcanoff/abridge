import CoreFoundation
@preconcurrency import EventKit
import Foundation

enum EventKitDeserialization {
    static func optionalString(_ value: Any?) throws -> String? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let string = value as? String else {
            throw EventKitProviderError.invalidArguments("Expected string or null")
        }
        return string
    }

    static func optionalInt(_ value: Any?) throws -> Int? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if value is Bool { throw EventKitProviderError.invalidArguments("Expected integer or null") }
        if let int = value as? Int { return int }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                throw EventKitProviderError.invalidArguments("Expected integer or null")
            }
            return number.intValue
        }
        throw EventKitProviderError.invalidArguments("Expected integer or null")
    }

    static func optionalBool(_ value: Any?) throws -> Bool? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let bool = value as? Bool else {
            throw EventKitProviderError.invalidArguments("Expected boolean or null")
        }
        return bool
    }

    static func optionalURL(_ value: Any?) throws -> URL? {
        guard let string = try optionalString(value) else { return nil }
        guard let url = URL(string: string) else {
            throw EventKitProviderError.invalidArguments("url must be a valid URL string")
        }
        return url
    }

    static func optionalISO8601Date(_ value: Any?) throws -> Date? {
        guard let string = try optionalString(value) else { return nil }
        guard let date = parseISO8601Date(string) else {
            throw EventKitProviderError.invalidArguments("Expected valid ISO8601 date-time")
        }
        return date
    }

    static func dateComponents(from value: Any?) throws -> DateComponents? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let dictionary = value as? [String: Any] else {
            throw EventKitProviderError.invalidArguments("date components must be an object or null")
        }

        var components = DateComponents()
        components.year = try optionalInt(dictionary["year"])
        components.month = try optionalInt(dictionary["month"])
        components.day = try optionalInt(dictionary["day"])
        components.hour = try optionalInt(dictionary["hour"])
        components.minute = try optionalInt(dictionary["minute"])
        components.second = try optionalInt(dictionary["second"])
        components.nanosecond = try optionalInt(dictionary["nanosecond"])
        components.weekday = try optionalInt(dictionary["weekday"])
        components.weekdayOrdinal = try optionalInt(dictionary["weekday_ordinal"])
        components.quarter = try optionalInt(dictionary["quarter"])
        components.weekOfMonth = try optionalInt(dictionary["week_of_month"])
        components.weekOfYear = try optionalInt(dictionary["week_of_year"])
        components.yearForWeekOfYear = try optionalInt(dictionary["year_for_week_of_year"])
        components.isLeapMonth = try optionalBool(dictionary["is_leap_month"])

        if let timeZoneValue = dictionary["time_zone"] {
            if timeZoneValue is NSNull {
                components.timeZone = nil
            } else if let identifier = timeZoneValue as? String {
                guard let timeZone = TimeZone(identifier: identifier) else {
                    throw EventKitProviderError.invalidArguments("time_zone must be a valid timezone identifier")
                }
                components.timeZone = timeZone
            } else {
                throw EventKitProviderError.invalidArguments("time_zone must be a string or null")
            }
        }

        if let calendarValue = dictionary["calendar"] {
            if calendarValue is NSNull {
                components.calendar = nil
            } else if let calendarDictionary = calendarValue as? [String: Any] {
                components.calendar = try foundationCalendar(from: calendarDictionary)
            } else {
                throw EventKitProviderError.invalidArguments("calendar must be an object or null")
            }
        }

        return components
    }

    static func foundationCalendar(from dictionary: [String: Any]) throws -> Calendar {
        var calendar = Calendar.current
        if dictionary.keys.contains("identifier") {
            if dictionary["identifier"] is NSNull {
                throw EventKitProviderError.invalidArguments("calendar identifier must be a string or null")
            }
            guard let identifierString = dictionary["identifier"] as? String,
                  let identifier = calendarIdentifier(from: identifierString)
            else {
                throw EventKitProviderError.invalidArguments("calendar identifier must be a valid calendar identifier")
            }
            calendar = Calendar(identifier: identifier)
        }
        if let localeIdentifier = try optionalString(dictionary["locale"]) {
            calendar.locale = Locale(identifier: localeIdentifier)
        }
        if let timeZoneIdentifier = try optionalString(dictionary["time_zone"]) {
            guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
                throw EventKitProviderError.invalidArguments("calendar time_zone must be a valid timezone identifier")
            }
            calendar.timeZone = timeZone
        }
        if let firstWeekday = try optionalInt(dictionary["first_weekday"]) {
            calendar.firstWeekday = firstWeekday
        }
        if let minimumDays = try optionalInt(dictionary["minimum_days_in_first_week"]) {
            calendar.minimumDaysInFirstWeek = minimumDays
        }
        return calendar
    }

    static func parseISO8601Date(_ value: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: value) {
            return date
        }

        let internetDateTime = ISO8601DateFormatter()
        internetDateTime.formatOptions = [.withInternetDateTime]
        return internetDateTime.date(from: value)
    }

    private static let calendarIdentifierLookup: [String: Calendar.Identifier] = [
        "gregorian": .gregorian,
        "buddhist": .buddhist,
        "chinese": .chinese,
        "coptic": .coptic,
        "ethiopic_amete_mihret": .ethiopicAmeteMihret,
        "ethiopic_amete_alem": .ethiopicAmeteAlem,
        "hebrew": .hebrew,
        "iso8601": .iso8601,
        "indian": .indian,
        "islamic": .islamic,
        "islamic_civil": .islamicCivil,
        "islamic_tabular": .islamicTabular,
        "islamic_umm_al_qura": .islamicUmmAlQura,
        "japanese": .japanese,
        "persian": .persian,
        "republic_of_china": .republicOfChina,
        "bangla": .bangla,
        "gujarati": .gujarati,
        "kannada": .kannada,
        "malayalam": .malayalam,
        "marathi": .marathi,
        "odia": .odia,
        "tamil": .tamil,
        "telugu": .telugu,
        "vikram": .vikram,
        "dangi": .dangi,
        "vietnamese": .vietnamese,
    ]

    private static func calendarIdentifier(from string: String) -> Calendar.Identifier? {
        calendarIdentifierLookup[string]
    }
}

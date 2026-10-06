@preconcurrency import Contacts
import Foundation

extension ContactsDeserialization {
    static func dateComponents(from value: Any?) throws -> DateComponents? {
        guard let value else { return nil }
        if value is NSNull {
            return nil
        }
        guard let dictionary = value as? [String: Any] else {
            throw ContactsProviderError.invalidArguments("date components must be an object or null")
        }

        var components = DateComponents()
        components.era = try optionalInt(dictionary["era"])
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
                    throw ContactsProviderError.invalidArguments("time_zone must be a valid timezone identifier")
                }
                components.timeZone = timeZone
            } else {
                throw ContactsProviderError.invalidArguments("time_zone must be a string or null")
            }
        }

        components.calendar = try optionalCalendar(dictionary["calendar"])

        return components
    }

    static func optionalCalendar(_ value: Any?) throws -> Calendar? {
        guard let value else { return nil }
        if value is NSNull {
            return nil
        }
        guard let dictionary = value as? [String: Any] else {
            throw ContactsProviderError.invalidArguments("calendar must be an object or null")
        }
        if dictionary.keys.contains("identifier"),
           dictionary["identifier"] is NSNull
        {
            return nil
        }
        return try foundationCalendar(from: dictionary)
    }

    static func foundationCalendar(from dictionary: [String: Any]) throws -> Calendar {
        var calendar = Calendar.current
        if dictionary.keys.contains("identifier"),
           !(dictionary["identifier"] is NSNull)
        {
            guard let identifierString = dictionary["identifier"] as? String,
                  let identifier = calendarIdentifier(from: identifierString)
            else {
                throw ContactsProviderError.invalidArguments("calendar identifier must be a valid calendar identifier")
            }
            calendar = Calendar(identifier: identifier)
        }
        if let localeIdentifier = try optionalString(dictionary["locale"]) {
            calendar.locale = Locale(identifier: localeIdentifier)
        }
        if let timeZoneIdentifier = try optionalString(dictionary["time_zone"]) {
            guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
                throw ContactsProviderError.invalidArguments("calendar time_zone must be a valid timezone identifier")
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

    static func calendarIdentifier(from string: String) -> Calendar.Identifier? {
        calendarIdentifierLookup[string]
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
}

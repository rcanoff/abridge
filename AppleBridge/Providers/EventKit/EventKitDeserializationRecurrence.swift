import CoreFoundation
@preconcurrency import EventKit
import Foundation

extension EventKitDeserialization {
    static func recurrenceRules(from value: Any?) throws -> [EKRecurrenceRule]? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let array = value as? [Any] else {
            throw EventKitProviderError.invalidArguments("recurrence_rules must be an array or null")
        }
        return try array.map { element in
            guard let dictionary = element as? [String: Any] else {
                throw EventKitProviderError.invalidArguments("recurrence rule entries must be objects")
            }
            return try recurrenceRule(from: dictionary)
        }
    }

    private static func recurrenceRule(from dictionary: [String: Any]) throws -> EKRecurrenceRule {
        guard let frequencyString = dictionary["frequency"] as? String else {
            throw EventKitProviderError.invalidArguments("recurrence rule frequency is required")
        }
        let frequency = try recurrenceFrequency(from: frequencyString)
        let interval = try optionalInt(dictionary["interval"]) ?? 1
        let end = try recurrenceEnd(from: dictionary["recurrence_end"])
        let daysOfWeek = try recurrenceDaysOfWeek(from: dictionary["days_of_the_week"])
        let daysOfMonth = try numberArray(from: dictionary["days_of_the_month"])
        let daysOfYear = try numberArray(from: dictionary["days_of_the_year"])
        let monthsOfYear = try numberArray(from: dictionary["months_of_the_year"])
        let weeksOfYear = try numberArray(from: dictionary["weeks_of_the_year"])
        let setPositions = try numberArray(from: dictionary["set_positions"])

        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: daysOfMonth,
            monthsOfTheYear: monthsOfYear,
            weeksOfTheYear: weeksOfYear,
            daysOfTheYear: daysOfYear,
            setPositions: setPositions,
            end: end
        )
    }

    private static func recurrenceEnd(from value: Any?) throws -> EKRecurrenceEnd? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let dictionary = value as? [String: Any] else {
            throw EventKitProviderError.invalidArguments("recurrence_end must be an object or null")
        }

        if let endDate = try optionalISO8601Date(dictionary["end_date"]) {
            return EKRecurrenceEnd(end: endDate)
        }

        if let occurrenceCount = try optionalInt(dictionary["occurrence_count"]), occurrenceCount > 0 {
            return EKRecurrenceEnd(occurrenceCount: occurrenceCount)
        }

        return nil
    }

    private static func recurrenceDaysOfWeek(from value: Any?) throws -> [EKRecurrenceDayOfWeek]? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let array = value as? [Any] else {
            throw EventKitProviderError.invalidArguments("days_of_the_week must be an array or null")
        }

        return try array.map { element in
            guard let dictionary = element as? [String: Any],
                  let dayRaw = try optionalInt(dictionary["day_of_the_week"]),
                  let ekDay = EKWeekday(rawValue: dayRaw)
            else {
                throw EventKitProviderError.invalidArguments("days_of_the_week entries require day_of_the_week")
            }
            let weekNumber = try optionalInt(dictionary["week_number"]) ?? 0
            return EKRecurrenceDayOfWeek(ekDay, weekNumber: weekNumber)
        }
    }

    private static func numberArray(from value: Any?) throws -> [NSNumber]? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let array = value as? [Any] else {
            throw EventKitProviderError.invalidArguments("Expected number array or null")
        }
        return try array.map { element in
            if element is Bool {
                throw EventKitProviderError.invalidArguments("Expected integer in number array")
            }
            if let int = element as? Int { return NSNumber(value: int) }
            if let number = element as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    throw EventKitProviderError.invalidArguments("Expected integer in number array")
                }
                guard EventKitDeserialization.isIntegralNumber(number) else {
                    throw EventKitProviderError.invalidArguments("Expected integer in number array")
                }
                return number
            }
            throw EventKitProviderError.invalidArguments("Expected integer in number array")
        }
    }

    private static func recurrenceFrequency(from string: String) throws -> EKRecurrenceFrequency {
        switch string {
        case "daily": .daily
        case "weekly": .weekly
        case "monthly": .monthly
        case "yearly": .yearly
        default:
            throw EventKitProviderError.invalidArguments("Invalid recurrence frequency: \(string)")
        }
    }
}

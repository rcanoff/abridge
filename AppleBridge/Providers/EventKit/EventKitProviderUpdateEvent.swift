@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct UpdateEventArguments {
        let eventIdentifier: String
        let calendarIdentifier: OptionalField<String>
        let title: OptionalField<String>
        let notes: OptionalField<String>
        let location: OptionalField<String>
        let url: OptionalField<URL>
        let timeZone: OptionalField<TimeZone>
        let startDate: OptionalField<Date>
        let endDate: OptionalField<Date>
        let isAllDay: OptionalField<Bool>
        let availability: OptionalField<EKEventAvailability>
        let structuredLocation: OptionalField<EKStructuredLocation>
        let alarms: OptionalField<[EKAlarm]>
        let recurrenceRules: OptionalField<[EKRecurrenceRule]>
    }

    func updateEvent(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let arguments = try parseUpdateEventArguments(payloadJson)
            guard let event = try store.fetchEvent(withIdentifier: arguments.eventIdentifier) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown event_identifier: \(arguments.eventIdentifier)"
                )
            }

            try applyUpdateEventArguments(arguments, to: event)
            try store.saveEvent(event, commit: true)

            let payload = try EventKitSerialization.jsonString(
                from: serializedEventJSONObject(from: event)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    private func applyUpdateEventArguments(_ arguments: UpdateEventArguments, to event: EKEvent) throws {
        try applyOptionalEventCalendarIdentifier(from: arguments, to: event)
        try applyOptionalEventTitle(from: arguments, to: event)
        applyOptionalEventStringFields(from: arguments, to: event)
        try applyOptionalEventStartEndDates(from: arguments, to: event)
        try applyOptionalEventAllDay(from: arguments, to: event)
        applyOptionalEventAvailability(from: arguments, to: event)
        applyOptionalEventStructuredLocation(from: arguments, to: event)
        applyOptionalEventCollectionFields(from: arguments, to: event)
        try validateEventDateRange(for: event)
    }

    private func applyOptionalEventCalendarIdentifier(
        from arguments: UpdateEventArguments,
        to event: EKEvent
    ) throws {
        switch arguments.calendarIdentifier {
        case .absent:
            return
        case let .present(calendarIdentifier):
            guard let calendarIdentifier else {
                throw EventKitProviderError.invalidArguments("calendar_identifier must not be empty")
            }
            guard !calendarIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw EventKitProviderError.invalidArguments("calendar_identifier must not be empty")
            }
            let calendars = try eventCalendars(calendarIdentifier: calendarIdentifier)
            guard let calendar = calendars.first else {
                throw EventKitProviderError.invalidArguments(
                    "Unknown calendar_identifier: \(calendarIdentifier)"
                )
            }
            event.calendar = calendar
        }
    }

    private func applyOptionalEventTitle(from arguments: UpdateEventArguments, to event: EKEvent) throws {
        switch arguments.title {
        case .absent:
            return
        case let .present(title):
            guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw EventKitProviderError.invalidArguments("title must not be empty")
            }
            event.title = title
        }
    }

    private func applyOptionalEventStringFields(from arguments: UpdateEventArguments, to event: EKEvent) {
        switch arguments.notes {
        case .absent:
            break
        case let .present(notes):
            event.notes = notes
        }

        switch arguments.location {
        case .absent:
            break
        case let .present(location):
            event.location = location
        }

        switch arguments.url {
        case .absent:
            break
        case let .present(url):
            event.url = url
        }

        switch arguments.timeZone {
        case .absent:
            break
        case let .present(timeZone):
            event.timeZone = timeZone
        }
    }

    private func applyOptionalEventStartEndDates(from arguments: UpdateEventArguments, to event: EKEvent) throws {
        switch arguments.startDate {
        case .absent:
            break
        case let .present(startDate):
            guard let startDate else {
                throw EventKitProviderError.invalidArguments("start_date must be an ISO8601 string")
            }
            event.startDate = startDate
        }

        switch arguments.endDate {
        case .absent:
            break
        case let .present(endDate):
            guard let endDate else {
                throw EventKitProviderError.invalidArguments("end_date must be an ISO8601 string")
            }
            event.endDate = endDate
        }
    }

    private func applyOptionalEventAllDay(from arguments: UpdateEventArguments, to event: EKEvent) throws {
        switch arguments.isAllDay {
        case .absent:
            return
        case let .present(isAllDay):
            guard let isAllDay else {
                throw EventKitProviderError.invalidArguments("is_all_day must be a boolean")
            }
            event.isAllDay = isAllDay
        }
    }

    private func applyOptionalEventAvailability(from arguments: UpdateEventArguments, to event: EKEvent) {
        switch arguments.availability {
        case .absent:
            return
        case let .present(availability):
            if let availability {
                event.availability = availability
            } else {
                event.availability = .notSupported
            }
        }
    }

    private func applyOptionalEventStructuredLocation(from arguments: UpdateEventArguments, to event: EKEvent) {
        switch arguments.structuredLocation {
        case .absent:
            return
        case let .present(structuredLocation):
            event.structuredLocation = structuredLocation
        }
    }

    private func applyOptionalEventCollectionFields(from arguments: UpdateEventArguments, to event: EKEvent) {
        switch arguments.alarms {
        case .absent:
            break
        case let .present(alarms):
            event.alarms = alarms
        }

        switch arguments.recurrenceRules {
        case .absent:
            break
        case let .present(recurrenceRules):
            event.recurrenceRules = recurrenceRules
        }
    }

    private func validateEventDateRange(for event: EKEvent) throws {
        if event.startDate > event.endDate {
            throw EventKitProviderError.invalidArguments("start_date must not be after end_date")
        }
    }

    private func parseUpdateEventArguments(_ payloadJson: String) throws -> UpdateEventArguments {
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let eventIdentifier = try parseEventIdentifierArguments(payloadJson)

        let timeZone: OptionalField<TimeZone>
        switch try EventKitDeserialization.optionalPresentString(dictionary, key: "time_zone") {
        case .absent:
            timeZone = .absent
        case let .present(timeZoneIdentifier):
            if let timeZoneIdentifier {
                guard let resolved = TimeZone(identifier: timeZoneIdentifier) else {
                    throw EventKitProviderError.invalidArguments("time_zone must be a valid timezone identifier")
                }
                timeZone = .present(resolved)
            } else {
                timeZone = .present(nil)
            }
        }

        return try UpdateEventArguments(
            eventIdentifier: eventIdentifier,
            calendarIdentifier: EventKitDeserialization.optionalPresentString(dictionary, key: "calendar_identifier"),
            title: EventKitDeserialization.optionalPresentString(dictionary, key: "title"),
            notes: EventKitDeserialization.optionalPresentString(dictionary, key: "notes"),
            location: EventKitDeserialization.optionalPresentString(dictionary, key: "location"),
            url: EventKitDeserialization.optionalPresentURL(dictionary, key: "url"),
            timeZone: timeZone,
            startDate: EventKitDeserialization.optionalPresentISO8601Date(dictionary, key: "start_date"),
            endDate: EventKitDeserialization.optionalPresentISO8601Date(dictionary, key: "end_date"),
            isAllDay: EventKitDeserialization.optionalPresentBool(dictionary, key: "is_all_day"),
            availability: EventKitDeserialization.optionalPresentEventAvailability(dictionary, key: "availability"),
            structuredLocation: EventKitDeserialization.optionalPresentStructuredLocation(
                dictionary,
                key: "structured_location"
            ),
            alarms: EventKitDeserialization.optionalPresentAlarms(dictionary, key: "alarms"),
            recurrenceRules: EventKitDeserialization.optionalPresentRecurrenceRules(
                dictionary,
                key: "recurrence_rules"
            )
        )
    }
}

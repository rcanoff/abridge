import CoreGraphics
@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct UpdateCalendarArguments {
        let calendarIdentifier: String
        let title: OptionalField<String>
        let cgColor: OptionalField<CGColor>
        let sourceIdentifier: OptionalField<String>
    }

    func updateCalendar(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let arguments = try parseUpdateCalendarArguments(payloadJson)
            let calendars = try eventCalendars(calendarIdentifier: arguments.calendarIdentifier)
            guard let calendar = calendars.first else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown calendar_identifier: \(arguments.calendarIdentifier)"
                )
            }

            try applyUpdateCalendarArguments(arguments, to: calendar)
            try store.saveCalendar(calendar, commit: true)

            let payload = try EventKitSerialization.jsonString(
                from: EventKitSerialization.calendarJSONObject(from: calendar)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    private func applyUpdateCalendarArguments(_ arguments: UpdateCalendarArguments, to calendar: EKCalendar) throws {
        switch arguments.title {
        case .absent:
            break
        case let .present(title):
            guard let title else { return }
            calendar.title = title
        }

        switch arguments.cgColor {
        case .absent:
            break
        case let .present(cgColor):
            calendar.cgColor = cgColor
        }

        switch arguments.sourceIdentifier {
        case .absent:
            break
        case let .present(sourceIdentifier):
            guard let sourceIdentifier else { return }
            calendar.source = try resolveEventSource(sourceIdentifier: sourceIdentifier)
        }
    }

    private func parseUpdateCalendarArguments(_ payloadJson: String) throws -> UpdateCalendarArguments {
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        let calendarIdentifier = SchemaTrustedPayload.requiredString(dictionary, "calendar_identifier")

        return try UpdateCalendarArguments(
            calendarIdentifier: calendarIdentifier,
            title: EventKitDeserialization.optionalPresentString(dictionary, key: "title"),
            cgColor: EventKitDeserialization.optionalPresentCGColor(dictionary, key: "cg_color"),
            sourceIdentifier: EventKitDeserialization.optionalPresentString(dictionary, key: "source_identifier")
        )
    }
}

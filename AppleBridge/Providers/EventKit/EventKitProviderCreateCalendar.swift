import CoreGraphics
@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct CreateCalendarArguments {
        let title: String
        let cgColor: CGColor?
        let sourceIdentifier: String?
    }

    func createCalendar(payloadJson: String) -> ProviderResponse {
        guard isEventAuthorized else {
            return errorResponse(code: "permission_denied", message: "Calendars access not granted")
        }

        do {
            let arguments = try parseCreateCalendarArguments(payloadJson)
            let calendar = store.makeEventCalendar()
            calendar.title = arguments.title
            if let cgColor = arguments.cgColor {
                calendar.cgColor = cgColor
            }

            let source = try resolveEventSource(sourceIdentifier: arguments.sourceIdentifier)
            calendar.source = source

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

    func resolveEventSource(sourceIdentifier: String?) throws -> EKSource {
        if let sourceIdentifier {
            guard let source = store.sources().first(where: { $0.sourceIdentifier == sourceIdentifier }) else {
                throw EventKitProviderError.invalidArguments(
                    "Unknown source_identifier: \(sourceIdentifier)"
                )
            }
            return source
        }

        guard let source = store.defaultEventSource() else {
            throw EventKitProviderError.invalidArguments("No calendar source is available")
        }
        return source
    }

    private func parseCreateCalendarArguments(_ payloadJson: String) throws -> CreateCalendarArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("title is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        guard let title = dictionary["title"] as? String else {
            throw EventKitProviderError.invalidArguments("title is required")
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EventKitProviderError.invalidArguments("title must not be empty")
        }

        return try CreateCalendarArguments(
            title: title,
            cgColor: EventKitDeserialization.cgColor(from: dictionary["cg_color"]),
            sourceIdentifier: EventKitDeserialization.optionalString(dictionary["source_identifier"])
        )
    }
}

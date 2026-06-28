import CoreGraphics
@preconcurrency import EventKit
import Foundation

extension EventKitProvider {
    struct CreateListArguments {
        let title: String
        let cgColor: CGColor?
        let sourceIdentifier: String?
    }

    func createList(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let arguments = try parseCreateListArguments(payloadJson)
            let calendar = store.makeReminderCalendar()
            calendar.title = arguments.title
            if let cgColor = arguments.cgColor {
                calendar.cgColor = cgColor
            }

            let source = try resolveReminderSource(sourceIdentifier: arguments.sourceIdentifier)
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

    private func resolveReminderSource(sourceIdentifier: String?) throws -> EKSource {
        if let sourceIdentifier {
            guard let source = store.sources().first(where: { $0.sourceIdentifier == sourceIdentifier }) else {
                throw EventKitProviderError.invalidArguments(
                    "Unknown source_identifier: \(sourceIdentifier)"
                )
            }
            return source
        }

        guard let source = store.defaultReminderSource() else {
            throw EventKitProviderError.invalidArguments("No reminder source is available")
        }
        return source
    }

    private func parseCreateListArguments(_ payloadJson: String) throws -> CreateListArguments {
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

        return try CreateListArguments(
            title: title,
            cgColor: EventKitDeserialization.cgColor(from: dictionary["cg_color"]),
            sourceIdentifier: EventKitDeserialization.optionalString(dictionary["source_identifier"])
        )
    }
}

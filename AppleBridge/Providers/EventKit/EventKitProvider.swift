@preconcurrency import EventKit
import Foundation

enum EventKitProviderError: Error, Equatable {
    case permissionDenied
    case serializationFailed
    case eventKitError(String)
    case unknownOperation(String)
    case invalidArguments(String)
    case reminderFetchTimedOut
}

@MainActor
protocol EventKitStoreing {
    func reminderAuthorizationStatus() -> EKAuthorizationStatus
    func eventAuthorizationStatus() -> EKAuthorizationStatus
    func reminderCalendars() -> [EKCalendar]
    func eventCalendars() -> [EKCalendar]
    func predicateForReminders(in calendars: [EKCalendar]) -> NSPredicate
    func predicateForIncompleteReminders(
        withDueDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]
    ) -> NSPredicate
    func predicateForCompletedReminders(
        withCompletionDateStarting startDate: Date?,
        ending endDate: Date?,
        calendars: [EKCalendar]
    ) -> NSPredicate
    func fetchReminders(matching predicate: NSPredicate) throws -> [EKReminder]
    func fetchReminder(withIdentifier id: String) throws -> EKReminder?
    func makeReminder() -> EKReminder
    func saveReminder(_ reminder: EKReminder, commit: Bool) throws
    func removeReminder(_ reminder: EKReminder, commit: Bool) throws
    func sources() -> [EKSource]
    func defaultReminderSource() -> EKSource?
    func defaultEventSource() -> EKSource?
    func makeReminderCalendar() -> EKCalendar
    func makeEventCalendar() -> EKCalendar
    func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws
    func removeCalendar(_ calendar: EKCalendar, commit: Bool) throws
    func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]) -> NSPredicate
    func fetchEvents(matching predicate: NSPredicate) throws -> [EKEvent]
    func fetchEvent(withIdentifier id: String) throws -> EKEvent?
    func makeEvent() -> EKEvent
    func saveEvent(_ event: EKEvent, commit: Bool) throws
    func removeEvent(_ event: EKEvent, commit: Bool) throws
    func canRespondToInvitation(for event: EKEvent) -> Bool
    func acceptEventInvitation(_ event: EKEvent) throws
    func declineEventInvitation(_ event: EKEvent) throws
    func tentativeEventInvitation(_ event: EKEvent) throws
    func eventIdentifier(for event: EKEvent) -> String?
}

extension EventKitStoreing {
    func eventIdentifier(for event: EKEvent) -> String? {
        event.eventIdentifier
    }
}

/// EventKit adapter: JSON ↔ Apple types. Pure schema validation is Rust (`arg_validation`).
/// This layer keeps mapping/runtime checks (permission, unknown ids, TimeZone).
@MainActor
final class EventKitProvider {
    let store: any EventKitStoreing

    init(store: any EventKitStoreing = LiveEventKitStore()) {
        self.store = store
    }

    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "list_lists":
            listLists()
        case "list_calendars":
            listCalendars()
        case "list_reminders", "get_reminder", "search_reminders", "list_events", "search_events", "get_event":
            handleReadOperation(operation: operation, payloadJson: payloadJson)
        case "create_reminder", "create_list", "create_calendar", "create_event", "update_reminder", "update_calendar",
             "update_event",
             "move_reminder", "move_event",
             "delete_reminder",
             "delete_list", "delete_calendar", "delete_event", "complete_reminder", "uncomplete_reminder",
             "set_reminder_alarms", "set_event_alarms",
             "set_reminder_recurrence", "set_event_recurrence",
             "accept_invitation", "decline_invitation", "tentative_invitation":
            handleMutationOperation(operation: operation, payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown operation: \(operation)")
        }
    }

    private func listLists() -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let lists = store.reminderCalendars().map(EventKitSerialization.calendarJSONObject)
            let payload = try EventKitSerialization.jsonString(from: lists)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch {
            return providerError(from: error)
        }
    }

    func listReminders(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let calendarIdentifier = try parseOptionalCalendarIdentifierArguments(payloadJson)
            let predicate = try reminderPredicate(listID: calendarIdentifier)
            let reminders = try store.fetchReminders(matching: predicate)
            let payloadObjects = reminders.map(EventKitSerialization.reminderJSONObject)
            let payload = try EventKitSerialization.jsonString(from: payloadObjects)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    func getReminder(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let reminderID = try parseReminderIDArguments(payloadJson)
            guard let reminder = try store.fetchReminder(withIdentifier: reminderID) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown calendar_item_identifier: \(reminderID)"
                )
            }
            let payload = try EventKitSerialization.jsonString(
                from: EventKitSerialization.reminderJSONObject(from: reminder)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    var isAuthorized: Bool {
        switch store.reminderAuthorizationStatus() {
        case .fullAccess:
            true
        default:
            false
        }
    }

    func parseJSONObject(from data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw EventKitProviderError.invalidArguments("Arguments must be valid JSON object")
        }

        guard let dictionary = object as? [String: Any] else {
            throw EventKitProviderError.invalidArguments("Arguments must be a JSON object")
        }

        return dictionary
    }

    private func parseOptionalCalendarIdentifierArguments(_ payloadJson: String) throws -> String? {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        guard dictionary.keys.contains("calendar_identifier") else {
            return nil
        }

        if let calendarIdentifier = dictionary["calendar_identifier"] as? String {
            return calendarIdentifier
        }

        if dictionary["calendar_identifier"] is NSNull {
            return nil
        }

        throw EventKitProviderError.invalidArguments("calendar_identifier must be a string or null")
    }

    func parseReminderIDArguments(_ payloadJson: String) throws -> String {
        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        // Required non-empty calendar_item_identifier is schema-owned (Rust).
        return SchemaTrustedPayload.requiredString(dictionary, "calendar_item_identifier")
    }

    private func reminderPredicate(listID: String?) throws -> NSPredicate {
        let calendars = try reminderCalendars(calendarIdentifier: listID)
        return store.predicateForReminders(in: calendars)
    }

    func providerErrorResponse(from error: EventKitProviderError) -> ProviderResponse {
        switch error {
        case .permissionDenied:
            errorResponse(code: "permission_denied", message: "Reminders access not granted")
        case let .invalidArguments(message):
            errorResponse(code: "invalid_arguments", message: message)
        case .serializationFailed:
            errorResponse(code: "eventkit_error", message: "Failed to serialize reminders")
        case let .eventKitError(message):
            errorResponse(code: "eventkit_error", message: message)
        case let .unknownOperation(message):
            errorResponse(code: "unknown_operation", message: message)
        case .reminderFetchTimedOut:
            errorResponse(code: "eventkit_error", message: "Reminder fetch timed out")
        }
    }

    func errorResponse(code: String, message: String) -> ProviderResponse {
        let payload: [String: String] = ["code": code, "message": message]
        let errorJson = (try? EventKitSerialization.jsonString(from: payload)) ?? #"{"code":"provider_error"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
    }

    func providerError(from error: Error) -> ProviderResponse {
        errorResponse(code: "eventkit_error", message: error.localizedDescription)
    }
}

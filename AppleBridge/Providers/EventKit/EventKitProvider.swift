@preconcurrency import EventKit
import Foundation

enum EventKitProviderError: Error, Equatable {
    case permissionDenied
    case serializationFailed
    case eventKitError(String)
    case unknownOperation(String)
    case invalidArguments(String)
}

protocol EventKitStoreing {
    func reminderAuthorizationStatus() -> EKAuthorizationStatus
    func reminderCalendars() -> [EKCalendar]
    func predicateForReminders(in calendars: [EKCalendar]) -> NSPredicate
    func fetchReminders(matching predicate: NSPredicate) -> [EKReminder]
}

final class LiveEventKitStore: EventKitStoreing, @unchecked Sendable {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func reminderAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    func reminderCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .reminder)
    }

    func predicateForReminders(in calendars: [EKCalendar]) -> NSPredicate {
        eventStore.predicateForReminders(in: calendars)
    }

    func fetchReminders(matching predicate: NSPredicate) -> [EKReminder] {
        let semaphore = DispatchSemaphore(value: 0)
        var fetched: [EKReminder] = []

        eventStore.fetchReminders(matching: predicate) { reminders in
            fetched = reminders ?? []
            semaphore.signal()
        }

        semaphore.wait()
        return fetched
    }
}

final class EventKitProvider: @unchecked Sendable {
    private let store: any EventKitStoreing

    init(store: any EventKitStoreing = LiveEventKitStore()) {
        self.store = store
    }

    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "list_lists":
            return listLists()
        case "list_reminders":
            return listReminders(payloadJson: payloadJson)
        default:
            return errorResponse(code: "unknown_operation", message: "Unknown operation: \(operation)")
        }
    }

    private func listLists() -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let lists = store.reminderCalendars().map(EventKitReminderMapping.listDictionary)
            let payload = try EventKitReminderMapping.jsonString(from: lists)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch {
            return providerError(from: error)
        }
    }

    private func listReminders(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Reminders access not granted")
        }

        do {
            let listID = try parseArguments(payloadJson)
            let predicate = try reminderPredicate(listID: listID)
            let reminders = store.fetchReminders(matching: predicate)
            let payloadObjects = reminders.map(EventKitReminderMapping.reminderDictionary)
            let payload = try EventKitReminderMapping.jsonString(from: payloadObjects)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as EventKitProviderError {
            switch error {
            case .permissionDenied:
                return errorResponse(code: "permission_denied", message: "Reminders access not granted")
            case .invalidArguments(let message):
                return errorResponse(code: "invalid_arguments", message: message)
            case .serializationFailed:
                return errorResponse(code: "eventkit_error", message: "Failed to serialize reminders")
            case .eventKitError(let message):
                return errorResponse(code: "eventkit_error", message: message)
            case .unknownOperation(let message):
                return errorResponse(code: "unknown_operation", message: message)
            }
        } catch {
            return providerError(from: error)
        }
    }

    private var isAuthorized: Bool {
        switch store.reminderAuthorizationStatus() {
        case .fullAccess:
            return true
        default:
            return false
        }
    }

    private func parseArguments(_ payloadJson: String) throws -> String? {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw EventKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw EventKitProviderError.invalidArguments("Arguments must be a JSON object")
        }

        guard dictionary.keys.contains("list_id") else {
            return nil
        }

        if let listID = dictionary["list_id"] as? String {
            return listID
        }

        if dictionary["list_id"] is NSNull {
            return nil
        }

        throw EventKitProviderError.invalidArguments("list_id must be a string or null")
    }

    private func reminderPredicate(listID: String?) throws -> NSPredicate {
        if let listID {
            let calendars = store.reminderCalendars()
            guard let calendar = calendars.first(where: { $0.calendarIdentifier == listID }) else {
                throw EventKitProviderError.invalidArguments("Unknown list_id: \(listID)")
            }
            return store.predicateForReminders(in: [calendar])
        }

        return store.predicateForReminders(in: store.reminderCalendars())
    }

    private func errorResponse(code: String, message: String) -> ProviderResponse {
        let payload: [String: String] = ["code": code, "message": message]
        let errorJson = (try? EventKitReminderMapping.jsonString(from: payload)) ?? #"{"code":"provider_error"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
    }

    private func providerError(from error: Error) -> ProviderResponse {
        errorResponse(code: "eventkit_error", message: error.localizedDescription)
    }
}
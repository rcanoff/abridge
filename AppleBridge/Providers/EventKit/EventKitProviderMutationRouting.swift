import Foundation

extension EventKitProvider {
    func handleMutationOperation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "create_reminder", "create_list", "create_calendar", "create_event":
            handleCreateMutation(operation: operation, payloadJson: payloadJson)
        case "update_reminder", "update_calendar", "update_event":
            handleUpdateMutation(operation: operation, payloadJson: payloadJson)
        case "move_reminder":
            moveReminder(payloadJson: payloadJson)
        case "move_event":
            moveEvent(payloadJson: payloadJson)
        case "delete_reminder", "delete_list", "delete_calendar", "delete_event":
            handleDeleteMutation(operation: operation, payloadJson: payloadJson)
        case "complete_reminder":
            completeReminder(payloadJson: payloadJson)
        case "uncomplete_reminder":
            uncompleteReminder(payloadJson: payloadJson)
        case "set_reminder_alarms", "set_event_alarms":
            handleSetAlarmsMutation(operation: operation, payloadJson: payloadJson)
        case "set_reminder_recurrence", "set_event_recurrence":
            handleSetRecurrenceMutation(operation: operation, payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown operation: \(operation)")
        }
    }

    private func handleCreateMutation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "create_reminder":
            createReminder(payloadJson: payloadJson)
        case "create_list":
            createList(payloadJson: payloadJson)
        case "create_calendar":
            createCalendar(payloadJson: payloadJson)
        case "create_event":
            createEvent(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown operation: \(operation)")
        }
    }

    private func handleUpdateMutation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "update_reminder":
            updateReminder(payloadJson: payloadJson)
        case "update_calendar":
            updateCalendar(payloadJson: payloadJson)
        case "update_event":
            updateEvent(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown operation: \(operation)")
        }
    }

    private func handleSetAlarmsMutation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "set_reminder_alarms":
            setReminderAlarms(payloadJson: payloadJson)
        case "set_event_alarms":
            setEventAlarms(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown operation: \(operation)")
        }
    }

    private func handleSetRecurrenceMutation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "set_reminder_recurrence":
            setReminderRecurrence(payloadJson: payloadJson)
        case "set_event_recurrence":
            setEventRecurrence(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown operation: \(operation)")
        }
    }

    private func handleDeleteMutation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "delete_reminder":
            deleteReminder(payloadJson: payloadJson)
        case "delete_list":
            deleteList(payloadJson: payloadJson)
        case "delete_calendar":
            deleteCalendar(payloadJson: payloadJson)
        case "delete_event":
            deleteEvent(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown operation: \(operation)")
        }
    }
}

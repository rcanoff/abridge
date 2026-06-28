import Foundation

extension EventKitProvider {
    func handleMutationOperation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "create_reminder", "create_list", "create_calendar":
            handleCreateMutation(operation: operation, payloadJson: payloadJson)
        case "update_reminder", "update_calendar":
            handleUpdateMutation(operation: operation, payloadJson: payloadJson)
        case "move_reminder":
            moveReminder(payloadJson: payloadJson)
        case "delete_reminder", "delete_list", "delete_calendar":
            handleDeleteMutation(operation: operation, payloadJson: payloadJson)
        case "complete_reminder":
            completeReminder(payloadJson: payloadJson)
        case "uncomplete_reminder":
            uncompleteReminder(payloadJson: payloadJson)
        case "set_reminder_alarms":
            setReminderAlarms(payloadJson: payloadJson)
        case "set_reminder_recurrence":
            setReminderRecurrence(payloadJson: payloadJson)
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
        default:
            errorResponse(code: "unknown_operation", message: "Unknown operation: \(operation)")
        }
    }
}

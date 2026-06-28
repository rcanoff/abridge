import Foundation

extension EventKitProvider {
    func handleReadOperation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "list_reminders":
            listReminders(payloadJson: payloadJson)
        case "get_reminder":
            getReminder(payloadJson: payloadJson)
        case "search_reminders":
            searchReminders(payloadJson: payloadJson)
        case "list_events":
            listEvents(payloadJson: payloadJson)
        case "search_events":
            searchEvents(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown operation: \(operation)")
        }
    }
}

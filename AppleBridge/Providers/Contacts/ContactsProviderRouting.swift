import Foundation

extension ContactsProvider {
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "list_contacts", "list_groups", "search_contacts", "get_contact":
            handleReadOperation(operation: operation, payloadJson: payloadJson)
        case "create_contact", "create_group":
            handleCreateOperation(operation: operation, payloadJson: payloadJson)
        case "update_contact", "update_group":
            handleUpdateOperation(operation: operation, payloadJson: payloadJson)
        case "delete_contact", "delete_group":
            handleDeleteOperation(operation: operation, payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown contacts operation: \(operation)")
        }
    }

    private func handleReadOperation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "list_contacts":
            listContacts(payloadJson: payloadJson)
        case "list_groups":
            listGroups(payloadJson: payloadJson)
        case "search_contacts":
            searchContacts(payloadJson: payloadJson)
        case "get_contact":
            getContact(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown contacts operation: \(operation)")
        }
    }

    private func handleCreateOperation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "create_contact":
            createContact(payloadJson: payloadJson)
        case "create_group":
            createGroup(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown contacts operation: \(operation)")
        }
    }

    private func handleUpdateOperation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "update_contact":
            updateContact(payloadJson: payloadJson)
        case "update_group":
            updateGroup(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown contacts operation: \(operation)")
        }
    }

    private func handleDeleteOperation(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "delete_contact":
            deleteContact(payloadJson: payloadJson)
        case "delete_group":
            deleteGroup(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown contacts operation: \(operation)")
        }
    }
}

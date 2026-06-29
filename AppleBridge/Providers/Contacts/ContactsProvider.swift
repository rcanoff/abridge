@preconcurrency import Contacts
import Foundation

enum ContactsProviderError: Error, Equatable {
    case permissionDenied
    case serializationFailed
    case contactsError(String)
    case unknownOperation(String)
    case invalidArguments(String)
}

@MainActor
enum LiveContactsEnvironment {
    static let sharedProvider = ContactsProvider()
}

@MainActor
final class ContactsProvider {
    let store: any ContactsStoreing

    init(store: any ContactsStoreing = LiveContactsStore()) {
        self.store = store
    }

    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        switch operation {
        case "list_contacts":
            listContacts(payloadJson: payloadJson)
        case "search_contacts":
            searchContacts(payloadJson: payloadJson)
        case "get_contact":
            getContact(payloadJson: payloadJson)
        case "create_contact":
            createContact(payloadJson: payloadJson)
        case "update_contact":
            updateContact(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown contacts operation: \(operation)")
        }
    }

    var isAuthorized: Bool {
        ContactsPermissionStatusMapper.map(store.contactsAuthorizationStatus()).grantsReadAccess
    }

    func parseJSONObject(from data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ContactsProviderError.invalidArguments("Arguments must be valid JSON object")
        }

        guard let dictionary = object as? [String: Any] else {
            throw ContactsProviderError.invalidArguments("Arguments must be a JSON object")
        }

        return dictionary
    }

    func providerErrorResponse(from error: ContactsProviderError) -> ProviderResponse {
        switch error {
        case .permissionDenied:
            errorResponse(code: "permission_denied", message: "Contacts access not granted")
        case let .invalidArguments(message):
            errorResponse(code: "invalid_arguments", message: message)
        case .serializationFailed:
            errorResponse(code: "contacts_error", message: "Failed to serialize contacts")
        case let .contactsError(message):
            errorResponse(code: "contacts_error", message: message)
        case let .unknownOperation(message):
            errorResponse(code: "unknown_operation", message: message)
        }
    }

    func errorResponse(code: String, message: String) -> ProviderResponse {
        let payload: [String: String] = ["code": code, "message": message]
        let errorJson = (try? ContactsSerialization.jsonString(from: payload)) ?? #"{"code":"provider_error"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
    }

    func providerError(from error: Error) -> ProviderResponse {
        errorResponse(code: "contacts_error", message: error.localizedDescription)
    }
}

@preconcurrency import Contacts
import Foundation

enum ContactsProviderError: Error, Equatable {
    case permissionDenied
    case serializationFailed
    case contactsError(String)
    case linkingUnavailable
    case unlinkingUnavailable
    case unknownOperation(String)
    case invalidArguments(String)

    static func unknownContainerIdentifier(_ identifier: String) -> ContactsProviderError {
        .invalidArguments(
            "Unknown container_identifier: \(identifier). Valid identifiers come from contacts_list_containers. "
                + "Omit container_identifier to use the default container."
        )
    }
}

@MainActor
enum LiveContactsEnvironment {
    static let sharedProvider = ContactsProvider()
}

/// Contacts adapter: JSON ↔ Contacts.framework. Pure schema validation is Rust.
@MainActor
final class ContactsProvider {
    let store: any ContactsStoreing

    init(store: any ContactsStoreing = LiveContactsStore()) {
        self.store = store
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
        case .linkingUnavailable:
            errorResponse(
                code: "contacts_error",
                message: "Linking contacts is unavailable: no public Contacts framework link API on this macOS version"
            )
        case .unlinkingUnavailable:
            errorResponse(
                code: "contacts_error",
                message: "Unlinking contacts is unavailable: "
                    + "no public Contacts framework unlink API on this macOS version"
            )
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

    /// Omitted or blank `container_identifier` uses the system default container.
    func resolvedContainerIdentifier(in dictionary: [String: Any]) -> String {
        if let identifier = SchemaTrustedPayload.optionalString(dictionary, "container_identifier") {
            return identifier
        }
        return store.defaultContainerIdentifier()
    }

    func contactJSONObject(from contact: CNContact, containerIdentifier: String? = nil) -> [String: Any] {
        var object = ContactsSerialization.contactJSONObject(from: contact)
        let resolved = store.containerIdentifiers(forContact: contact.identifier).first ?? containerIdentifier
        if let resolved {
            object["container_identifier"] = resolved
        }
        return object
    }
}

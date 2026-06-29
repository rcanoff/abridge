@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    struct CreateContactArguments {
        let containerIdentifier: String
        let contact: CNMutableContact
    }

    func createContact(payloadJson: String) -> ProviderResponse {
        guard isWriteAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts write access not granted")
        }

        do {
            let arguments = try parseCreateContactArguments(payloadJson)
            let saved = try store.createContact(in: arguments.containerIdentifier, contact: arguments.contact)
            let payload = try ContactsSerialization.jsonString(
                from: ContactsSerialization.contactJSONObject(from: saved)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    var isWriteAuthorized: Bool {
        ContactsPermissionStatusMapper.map(store.contactsAuthorizationStatus()).grantsWriteAccess
    }

    func parseCreateContactArguments(_ payloadJson: String) throws -> CreateContactArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContactsProviderError.invalidArguments(
                "container_identifier and at least one of given_name, family_name, or organization_name are required"
            )
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw ContactsProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        guard let containerIdentifier = dictionary["container_identifier"] as? String else {
            throw ContactsProviderError.invalidArguments("container_identifier is required")
        }
        let trimmedContainer = containerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContainer.isEmpty else {
            throw ContactsProviderError.invalidArguments("container_identifier must not be empty")
        }

        guard hasNonEmptyTrimmedName(in: dictionary) else {
            throw ContactsProviderError.invalidArguments(
                "At least one of given_name, family_name, or organization_name is required"
            )
        }

        let contact = try ContactsDeserialization.mutableContact(from: dictionary)
        return CreateContactArguments(containerIdentifier: trimmedContainer, contact: contact)
    }

    private func hasNonEmptyTrimmedName(in dictionary: [String: Any]) -> Bool {
        ["given_name", "family_name", "organization_name"].contains { key in
            guard let value = dictionary[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

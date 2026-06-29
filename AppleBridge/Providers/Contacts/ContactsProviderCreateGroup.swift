@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    struct CreateGroupArguments {
        let containerIdentifier: String
        let name: String
    }

    func createGroup(payloadJson: String) -> ProviderResponse {
        guard isWriteAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts write access not granted")
        }

        do {
            let arguments = try parseCreateGroupArguments(payloadJson)
            let saved = try store.createGroup(in: arguments.containerIdentifier, name: arguments.name)
            let payload = try ContactsSerialization.jsonString(
                from: ContactsSerialization.groupJSONObject(from: saved)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    func parseCreateGroupArguments(_ payloadJson: String) throws -> CreateGroupArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContactsProviderError.invalidArguments("container_identifier and name are required")
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

        guard let name = dictionary["name"] as? String else {
            throw ContactsProviderError.invalidArguments("name is required")
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ContactsProviderError.invalidArguments("name must not be empty")
        }

        return CreateGroupArguments(containerIdentifier: trimmedContainer, name: trimmedName)
    }
}
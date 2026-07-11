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
        guard let data = payloadJson.data(using: .utf8) else {
            throw ContactsProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        let containerIdentifier = SchemaTrustedPayload.requiredString(dictionary, "container_identifier")
        let trimmedContainer = containerIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContainer.isEmpty else {
            throw ContactsProviderError.invalidArguments("container_identifier must not be empty")
        }

        let name = SchemaTrustedPayload.requiredString(dictionary, "name")
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ContactsProviderError.invalidArguments("name must not be empty")
        }

        return CreateGroupArguments(containerIdentifier: trimmedContainer, name: trimmedName)
    }
}

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

        let trimmedContainer = SchemaTrustedPayload.requiredString(dictionary, "container_identifier")

        let trimmedName = SchemaTrustedPayload.requiredString(dictionary, "name")

        return CreateGroupArguments(containerIdentifier: trimmedContainer, name: trimmedName)
    }
}

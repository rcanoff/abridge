@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    func listGroups(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts access not granted")
        }

        do {
            let containerIdentifier = try parseListGroupsContainerIdentifierArguments(payloadJson)
            let groups = try store.fetchGroups(containerIdentifier: containerIdentifier)
            let payloadObjects = groups.map(ContactsSerialization.groupJSONObject)
            let payload = try ContactsSerialization.jsonString(from: payloadObjects)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    private func parseListGroupsContainerIdentifierArguments(_ payloadJson: String) throws -> String? {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw ContactsProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        guard dictionary.keys.contains("container_identifier") else {
            return nil
        }

        if let containerIdentifier = dictionary["container_identifier"] as? String {
            return containerIdentifier
        }

        if dictionary["container_identifier"] is NSNull {
            return nil
        }

        throw ContactsProviderError.invalidArguments("container_identifier must be a string or null")
    }
}
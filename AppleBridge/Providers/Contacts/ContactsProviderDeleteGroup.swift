@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    func deleteGroup(payloadJson: String) -> ProviderResponse {
        guard isWriteAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts write access not granted")
        }

        do {
            let groupIdentifier = try parseGroupIdentifierArguments(payloadJson)
            let groups = try store.fetchGroups(containerIdentifier: nil)
            guard let group = groups.first(where: { $0.identifier == groupIdentifier }) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown group_identifier: \(groupIdentifier)"
                )
            }

            let deletedIdentifier = group.identifier
            try store.deleteGroup(identifier: deletedIdentifier)

            let payload = try ContactsSerialization.jsonString(from: [
                "group_identifier": deletedIdentifier,
            ])
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    func parseGroupIdentifierArguments(_ payloadJson: String) throws -> String {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContactsProviderError.invalidArguments("group_identifier is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw ContactsProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        guard let groupIdentifier = dictionary["group_identifier"] as? String else {
            throw ContactsProviderError.invalidArguments("group_identifier is required")
        }

        let trimmed = groupIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContactsProviderError.invalidArguments("group_identifier must not be empty")
        }

        return trimmed
    }
}

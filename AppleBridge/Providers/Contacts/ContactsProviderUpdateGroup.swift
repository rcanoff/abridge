@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    struct UpdateGroupArguments {
        let groupIdentifier: String
        let fields: [String: Any]
    }

    func updateGroup(payloadJson: String) -> ProviderResponse {
        guard isWriteAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts write access not granted")
        }

        do {
            let arguments = try parseUpdateGroupArguments(payloadJson)
            let updated = try store.updateGroup(
                identifier: arguments.groupIdentifier,
                fields: arguments.fields
            )
            let payload = try ContactsSerialization.jsonString(
                from: ContactsSerialization.groupJSONObject(from: updated)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    func parseUpdateGroupArguments(_ payloadJson: String) throws -> UpdateGroupArguments {
        guard let data = payloadJson.data(using: .utf8) else {
            throw ContactsProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        let trimmedIdentifier = SchemaTrustedPayload.requiredString(dictionary, "group_identifier")

        var fields = dictionary
        fields.removeValue(forKey: "group_identifier")

        let unknownKeys = Set(fields.keys).subtracting(["name"]).sorted()
        if let unknownKey = unknownKeys.first {
            throw ContactsProviderError.invalidArguments("Unknown field: \(unknownKey)")
        }

        if let name = fields["name"] {
            if name is NSNull {
                // Explicit null clears the group name.
            } else if let nameString = name as? String {
                let trimmedName = nameString.trimmingCharacters(in: .whitespacesAndNewlines)
                fields["name"] = trimmedName
            } else {
                throw ContactsProviderError.invalidArguments("name must be a string or null")
            }
        }

        return UpdateGroupArguments(groupIdentifier: trimmedIdentifier, fields: fields)
    }
}

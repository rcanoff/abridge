@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    struct LinkContactsArguments {
        let fromContactIdentifier: String
        let toContactIdentifier: String
    }

    func linkContacts(payloadJson: String) -> ProviderResponse {
        guard isWriteAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts write access not granted")
        }

        do {
            let arguments = try parseLinkContactsArguments(payloadJson)
            let linked = try store.linkContacts(
                fromIdentifier: arguments.fromContactIdentifier,
                toIdentifier: arguments.toContactIdentifier
            )
            let payload = try ContactsSerialization.jsonString(
                from: ContactsSerialization.contactJSONObject(from: linked)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    func parseLinkContactsArguments(_ payloadJson: String) throws -> LinkContactsArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContactsProviderError.invalidArguments(
                "from_contact_identifier and to_contact_identifier are required"
            )
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw ContactsProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        let trimmedFrom = SchemaTrustedPayload.requiredString(dictionary, "from_contact_identifier")
        let trimmedTo = SchemaTrustedPayload.requiredString(dictionary, "to_contact_identifier")

        if trimmedFrom == trimmedTo {
            throw ContactsProviderError.invalidArguments(
                "from_contact_identifier and to_contact_identifier must differ"
            )
        }

        return LinkContactsArguments(
            fromContactIdentifier: trimmedFrom,
            toContactIdentifier: trimmedTo
        )
    }
}

@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    struct UpdateContactArguments {
        let contactIdentifier: String
        let fields: [String: Any]
    }

    func updateContact(payloadJson: String) -> ProviderResponse {
        guard isWriteAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts write access not granted")
        }

        do {
            let arguments = try parseUpdateContactArguments(payloadJson)
            let updated = try store.updateContact(
                identifier: arguments.contactIdentifier,
                fields: arguments.fields
            )
            let payload = try ContactsSerialization.jsonString(
                from: ContactsSerialization.contactJSONObject(from: updated)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    func parseUpdateContactArguments(_ payloadJson: String) throws -> UpdateContactArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContactsProviderError.invalidArguments("contact_identifier is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw ContactsProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let contactIdentifier = try parseContactIdentifierArguments(payloadJson)

        var fields = dictionary
        fields.removeValue(forKey: "contact_identifier")

        return UpdateContactArguments(contactIdentifier: contactIdentifier, fields: fields)
    }
}
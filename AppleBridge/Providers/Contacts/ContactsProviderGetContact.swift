@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    func getContact(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts access not granted")
        }

        do {
            let contactIdentifier = try parseContactIdentifierArguments(payloadJson)
            guard let contact = try store.fetchContact(identifier: contactIdentifier) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown contact_identifier: \(contactIdentifier)"
                )
            }
            let payload = try ContactsSerialization.jsonString(
                from: ContactsSerialization.contactJSONObject(from: contact)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    func parseContactIdentifierArguments(_ payloadJson: String) throws -> String {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContactsProviderError.invalidArguments("contact_identifier is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw ContactsProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        guard let contactIdentifier = dictionary["contact_identifier"] as? String else {
            throw ContactsProviderError.invalidArguments("contact_identifier is required")
        }

        let trimmed = contactIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContactsProviderError.invalidArguments("contact_identifier must not be empty")
        }

        return trimmed
    }
}

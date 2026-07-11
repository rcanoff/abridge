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
        guard let data = payloadJson.data(using: .utf8) else {
            throw ContactsProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)

        return SchemaTrustedPayload.requiredString(dictionary, "contact_identifier")
    }
}

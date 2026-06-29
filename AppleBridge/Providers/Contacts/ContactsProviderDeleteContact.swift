@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    func deleteContact(payloadJson: String) -> ProviderResponse {
        guard isWriteAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts write access not granted")
        }

        do {
            let contactIdentifier = try parseContactIdentifierArguments(payloadJson)
            guard let contact = try store.fetchContact(identifier: contactIdentifier) else {
                return errorResponse(
                    code: "invalid_arguments",
                    message: "Unknown contact_identifier: \(contactIdentifier)"
                )
            }

            let deletedIdentifier = contact.identifier
            try store.deleteContact(identifier: deletedIdentifier)

            let payload = try ContactsSerialization.jsonString(from: [
                "contact_identifier": deletedIdentifier,
            ])
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }
}
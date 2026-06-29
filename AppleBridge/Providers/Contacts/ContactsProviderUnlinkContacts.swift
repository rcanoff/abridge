@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    func unlinkContacts(payloadJson: String) -> ProviderResponse {
        guard isWriteAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts write access not granted")
        }

        do {
            let contactIdentifier = try parseContactIdentifierArguments(payloadJson)
            let unlinked = try store.unlinkContact(identifier: contactIdentifier)
            let payload = try ContactsSerialization.jsonString(
                from: ContactsSerialization.contactJSONObject(from: unlinked)
            )
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }
}

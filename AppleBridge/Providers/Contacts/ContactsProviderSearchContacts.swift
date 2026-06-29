@preconcurrency import Contacts
import Foundation

extension ContactsProvider {
    struct SearchContactsArguments {
        let name: String?
        let emailAddress: String?
        let phoneNumber: String?
        let containerIdentifier: String?
    }

    func searchContacts(payloadJson: String) -> ProviderResponse {
        guard isAuthorized else {
            return errorResponse(code: "permission_denied", message: "Contacts access not granted")
        }

        do {
            let arguments = try parseSearchContactsArguments(payloadJson)
            let contacts = try store.searchContacts(
                name: arguments.name,
                emailAddress: arguments.emailAddress,
                phoneNumber: arguments.phoneNumber,
                containerIdentifier: arguments.containerIdentifier
            )
            let payloadObjects = contacts.map(ContactsSerialization.contactJSONObject)
            let payload = try ContactsSerialization.jsonString(from: payloadObjects)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as ContactsProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return providerError(from: error)
        }
    }

    private func parseSearchContactsArguments(_ payloadJson: String) throws -> SearchContactsArguments {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContactsProviderError.invalidArguments("at least one search field required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw ContactsProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let name = try optionalStringArgument(named: "name", in: dictionary)
        let emailAddress = try optionalStringArgument(named: "email_address", in: dictionary)
        let phoneNumber = try optionalStringArgument(named: "phone_number", in: dictionary)
        let containerIdentifier = try optionalStringArgument(named: "container_identifier", in: dictionary)

        guard name != nil || emailAddress != nil || phoneNumber != nil else {
            throw ContactsProviderError.invalidArguments("at least one search field required")
        }

        return SearchContactsArguments(
            name: name,
            emailAddress: emailAddress,
            phoneNumber: phoneNumber,
            containerIdentifier: containerIdentifier
        )
    }

    private func optionalStringArgument(named key: String, in dictionary: [String: Any]) throws -> String? {
        guard dictionary.keys.contains(key) else {
            return nil
        }

        if dictionary[key] is NSNull {
            return nil
        }

        guard let value = dictionary[key] as? String else {
            throw ContactsProviderError.invalidArguments("\(key) must be a string or null")
        }

        return value
    }
}

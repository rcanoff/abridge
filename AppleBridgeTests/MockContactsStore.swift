@testable import AppleBridge
import Contacts
import Foundation

@MainActor
final class MockContactsStore: ContactsStoreing {
    var authorizationStatus: CNAuthorizationStatus = .authorized
    var contacts: [CNContact] = []
    var knownContainerIdentifiers: Set<String> = ["container-1"]
    var fetchError: ContactsProviderError?
    var linkingUnavailable = false

    func contactsAuthorizationStatus() -> CNAuthorizationStatus {
        authorizationStatus
    }

    func fetchContacts(containerIdentifier: String?) throws -> [CNContact] {
        if let fetchError {
            throw fetchError
        }

        if let containerIdentifier {
            guard knownContainerIdentifiers.contains(containerIdentifier) else {
                throw ContactsProviderError.invalidArguments(
                    "Unknown container_identifier: \(containerIdentifier)"
                )
            }
        }

        return contacts
    }

    func fetchContact(identifier: String) throws -> CNContact? {
        if let fetchError {
            throw fetchError
        }

        return contacts.first { $0.identifier == identifier }
    }

    func searchContacts(
        name: String?,
        emailAddress: String?,
        phoneNumber: String?,
        containerIdentifier: String?
    ) throws -> [CNContact] {
        if let fetchError {
            throw fetchError
        }

        if let containerIdentifier {
            guard knownContainerIdentifiers.contains(containerIdentifier) else {
                throw ContactsProviderError.invalidArguments(
                    "Unknown container_identifier: \(containerIdentifier)"
                )
            }
        }

        return contacts.filter { contact in
            if let name, !matchesName(contact, name) {
                return false
            }
            if let emailAddress, !matchesEmail(contact, emailAddress) {
                return false
            }
            if let phoneNumber, !matchesPhone(contact, phoneNumber) {
                return false
            }
            return true
        }
    }

    private func matchesName(_ contact: CNContact, _ name: String) -> Bool {
        let searchableFields = [
            contact.givenName,
            contact.familyName,
            contact.middleName,
            contact.nickname,
            contact.organizationName,
        ]
        let haystack = searchableFields.joined(separator: " ").lowercased()
        return haystack.contains(name.lowercased())
    }

    private func matchesEmail(_ contact: CNContact, _ emailAddress: String) -> Bool {
        contact.emailAddresses.contains { labeledValue in
            (labeledValue.value as String).localizedCaseInsensitiveContains(emailAddress)
        }
    }

    private func matchesPhone(_ contact: CNContact, _ phoneNumber: String) -> Bool {
        contact.phoneNumbers.contains { labeledValue in
            labeledValue.value.stringValue.localizedCaseInsensitiveContains(phoneNumber)
        }
    }

    func createContact(in containerIdentifier: String, contact: CNMutableContact) throws -> CNContact {
        if let fetchError {
            throw fetchError
        }

        guard knownContainerIdentifiers.contains(containerIdentifier) else {
            throw ContactsProviderError.invalidArguments(
                "Unknown container_identifier: \(containerIdentifier)"
            )
        }

        guard let saved = contact.mutableCopy() as? CNMutableContact else {
            throw ContactsProviderError.contactsError("Failed to copy contact")
        }

        contacts.append(saved)
        return saved
    }

    func deleteContact(identifier: String) throws {
        if let fetchError {
            throw fetchError
        }

        guard let index = contacts.firstIndex(where: { $0.identifier == identifier }) else {
            throw ContactsProviderError.invalidArguments("Unknown contact_identifier: \(identifier)")
        }

        contacts.remove(at: index)
    }

    func updateContact(identifier: String, fields: [String: Any]) throws -> CNContact {
        if let fetchError {
            throw fetchError
        }

        guard let index = contacts.firstIndex(where: { $0.identifier == identifier }) else {
            throw ContactsProviderError.invalidArguments("Unknown contact_identifier: \(identifier)")
        }

        guard let mutable = contacts[index].mutableCopy() as? CNMutableContact else {
            throw ContactsProviderError.contactsError("Failed to copy contact")
        }

        try ContactsDeserialization.applyWritableFields(from: fields, to: mutable)
        contacts[index] = mutable
        return mutable
    }

    func linkContacts(fromIdentifier: String, toIdentifier: String) throws -> CNContact {
        if let fetchError {
            throw fetchError
        }

        if linkingUnavailable {
            throw ContactsProviderError.linkingUnavailable
        }

        if fromIdentifier == toIdentifier {
            throw ContactsProviderError.invalidArguments(
                "from_contact_identifier and to_contact_identifier must differ"
            )
        }

        guard let fromIndex = contacts.firstIndex(where: { $0.identifier == fromIdentifier }) else {
            throw ContactsProviderError.invalidArguments(
                "Unknown from_contact_identifier: \(fromIdentifier)"
            )
        }

        guard let toContact = contacts.first(where: { $0.identifier == toIdentifier }) else {
            throw ContactsProviderError.invalidArguments(
                "Unknown to_contact_identifier: \(toIdentifier)"
            )
        }

        contacts.remove(at: fromIndex)
        return toContact
    }
}

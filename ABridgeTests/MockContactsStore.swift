@testable import ABridge
import Contacts
import Foundation

@MainActor
final class MockContactsStore: ContactsStoreing {
    var authorizationStatus: CNAuthorizationStatus = .authorized
    var contacts: [CNContact] = []
    var groups: [CNGroup] = []
    var knownContainerIdentifiers: Set<String> = ["container-1"]
    var defaultContainerIdentifierValue = "container-1"
    var contactContainers: [String: String] = [:]
    var lastCreatedGroupContainerIdentifier: String?
    var fetchError: ContactsProviderError?
    var linkingUnavailable = false
    var unlinkingUnavailable = false
    var lastFetchGroupsContainerIdentifier: String?

    func contactsAuthorizationStatus() -> CNAuthorizationStatus {
        authorizationStatus
    }

    func defaultContainerIdentifier() -> String {
        defaultContainerIdentifierValue
    }

    func listContainers() throws -> [ContactsContainerRecord] {
        if let fetchError {
            throw fetchError
        }

        return knownContainerIdentifiers.sorted().map { identifier in
            ContactsContainerRecord(
                identifier: identifier,
                name: identifier,
                type: "local",
                isDefault: identifier == defaultContainerIdentifierValue
            )
        }
    }

    func containerIdentifiers(forContact identifier: String) -> [String] {
        contactContainers[identifier].map { [$0] } ?? []
    }

    func fetchContacts(containerIdentifier: String?) throws -> [CNContact] {
        if let fetchError {
            throw fetchError
        }

        if let containerIdentifier {
            guard knownContainerIdentifiers.contains(containerIdentifier) else {
                throw ContactsProviderError.unknownContainerIdentifier(containerIdentifier)
            }
        }

        return contacts
    }

    func fetchGroups(containerIdentifier: String?) throws -> [CNGroup] {
        lastFetchGroupsContainerIdentifier = containerIdentifier

        if let fetchError {
            throw fetchError
        }

        if let containerIdentifier {
            guard knownContainerIdentifiers.contains(containerIdentifier) else {
                throw ContactsProviderError.unknownContainerIdentifier(containerIdentifier)
            }
        }

        return groups
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
                throw ContactsProviderError.unknownContainerIdentifier(containerIdentifier)
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

    func updateGroup(identifier: String, fields: [String: Any]) throws -> CNGroup {
        if let fetchError {
            throw fetchError
        }

        guard let index = groups.firstIndex(where: { $0.identifier == identifier }) else {
            throw ContactsProviderError.invalidArguments("Unknown group_identifier: \(identifier)")
        }

        guard let mutable = groups[index].mutableCopy() as? CNMutableGroup else {
            throw ContactsProviderError.contactsError("Failed to copy group")
        }

        try ContactsGroupDeserialization.applyWritableFields(from: fields, to: mutable)
        groups[index] = mutable
        return mutable
    }

    func createGroup(in containerIdentifier: String, name: String) throws -> CNGroup {
        if let fetchError {
            throw fetchError
        }

        guard knownContainerIdentifiers.contains(containerIdentifier) else {
            throw ContactsProviderError.unknownContainerIdentifier(containerIdentifier)
        }

        let group = CNMutableGroup()
        group.name = name
        groups.append(group)
        lastCreatedGroupContainerIdentifier = containerIdentifier
        return group
    }

    func createContact(in containerIdentifier: String, contact: CNMutableContact) throws -> CNContact {
        if let fetchError {
            throw fetchError
        }

        guard knownContainerIdentifiers.contains(containerIdentifier) else {
            throw ContactsProviderError.unknownContainerIdentifier(containerIdentifier)
        }

        guard let saved = contact.mutableCopy() as? CNMutableContact else {
            throw ContactsProviderError.contactsError("Failed to copy contact")
        }

        contacts.append(saved)
        contactContainers[saved.identifier] = containerIdentifier
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

    func deleteGroup(identifier: String) throws {
        if let fetchError {
            throw fetchError
        }

        guard let index = groups.firstIndex(where: { $0.identifier == identifier }) else {
            throw ContactsProviderError.invalidArguments("Unknown group_identifier: \(identifier)")
        }

        groups.remove(at: index)
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

    func unlinkContact(identifier: String) throws -> CNContact {
        if let fetchError {
            throw fetchError
        }

        if unlinkingUnavailable {
            throw ContactsProviderError.unlinkingUnavailable
        }

        guard let contact = try fetchContact(identifier: identifier) else {
            throw ContactsProviderError.invalidArguments("Unknown contact_identifier: \(identifier)")
        }

        return contact
    }
}

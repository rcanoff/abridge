@preconcurrency import Contacts
import Foundation

@MainActor
final class LiveContactsStore: ContactsStoreing {
    private let contactStore: CNContactStore

    init(contactStore: CNContactStore = CNContactStore()) {
        self.contactStore = contactStore
    }

    func contactsAuthorizationStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func fetchContacts(containerIdentifier: String?) throws -> [CNContact] {
        if let containerIdentifier {
            let containers = try contactStore.containers(matching: nil)
            guard containers.contains(where: { $0.identifier == containerIdentifier }) else {
                throw ContactsProviderError.invalidArguments(
                    "Unknown container_identifier: \(containerIdentifier)"
                )
            }
        }

        let request = CNContactFetchRequest(keysToFetch: ContactsKeyDescriptors.all)
        if let containerIdentifier {
            request.predicate = CNContact.predicateForContactsInContainer(withIdentifier: containerIdentifier)
        }

        var fetched: [CNContact] = []
        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                fetched.append(contact)
            }
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }

        return fetched
    }

    func fetchGroups(containerIdentifier: String?) throws -> [CNGroup] {
        if let containerIdentifier {
            let containers = try contactStore.containers(matching: nil)
            guard containers.contains(where: { $0.identifier == containerIdentifier }) else {
                throw ContactsProviderError.invalidArguments(
                    "Unknown container_identifier: \(containerIdentifier)"
                )
            }
        }

        let predicate: NSPredicate? = if let containerIdentifier {
            CNGroup.predicateForGroupsInContainer(withIdentifier: containerIdentifier)
        } else {
            nil
        }

        do {
            return try contactStore.groups(matching: predicate)
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }
    }

    func fetchContact(identifier: String) throws -> CNContact? {
        do {
            return try contactStore.unifiedContact(
                withIdentifier: identifier,
                keysToFetch: ContactsKeyDescriptors.all
            )
        } catch let error as CNError where error.code == .recordDoesNotExist {
            return nil
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }
    }

    func searchContacts(
        name: String?,
        emailAddress: String?,
        phoneNumber: String?,
        containerIdentifier: String?
    ) throws -> [CNContact] {
        if let containerIdentifier {
            let containers = try contactStore.containers(matching: nil)
            guard containers.contains(where: { $0.identifier == containerIdentifier }) else {
                throw ContactsProviderError.invalidArguments(
                    "Unknown container_identifier: \(containerIdentifier)"
                )
            }
        }

        var searchPredicates: [NSPredicate] = []
        if let name {
            searchPredicates.append(CNContact.predicateForContacts(matchingName: name))
        }
        if let emailAddress {
            searchPredicates.append(CNContact.predicateForContacts(matchingEmailAddress: emailAddress))
        }
        if let phoneNumber {
            searchPredicates.append(
                CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phoneNumber))
            )
        }

        var contactSets = try searchPredicates.map { predicate in
            try unifiedContacts(matching: predicate)
        }

        if let containerIdentifier {
            let containerContacts = try unifiedContacts(
                matching: CNContact.predicateForContactsInContainer(withIdentifier: containerIdentifier)
            )
            contactSets.append(containerContacts)
        }

        return ContactsSearchSupport.intersectContacts(contactSets)
    }

    func createGroup(in containerIdentifier: String, name: String) throws -> CNGroup {
        let containers = try contactStore.containers(matching: nil)
        guard containers.contains(where: { $0.identifier == containerIdentifier }) else {
            throw ContactsProviderError.invalidArguments(
                "Unknown container_identifier: \(containerIdentifier)"
            )
        }

        let group = CNMutableGroup()
        group.name = name
        let saveRequest = CNSaveRequest()
        saveRequest.add(group, toContainerWithIdentifier: containerIdentifier)
        do {
            try contactStore.execute(saveRequest)
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }

        return group
    }

    func createContact(in containerIdentifier: String, contact: CNMutableContact) throws -> CNContact {
        let containers = try contactStore.containers(matching: nil)
        guard containers.contains(where: { $0.identifier == containerIdentifier }) else {
            throw ContactsProviderError.invalidArguments(
                "Unknown container_identifier: \(containerIdentifier)"
            )
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: containerIdentifier)
        do {
            try contactStore.execute(saveRequest)
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }

        guard let saved = try fetchContact(identifier: contact.identifier) else {
            throw ContactsProviderError.contactsError("Failed to fetch created contact")
        }
        return saved
    }

    func deleteContact(identifier: String) throws {
        guard let existing = try fetchContact(identifier: identifier) else {
            throw ContactsProviderError.invalidArguments("Unknown contact_identifier: \(identifier)")
        }

        guard let mutable = existing.mutableCopy() as? CNMutableContact else {
            throw ContactsProviderError.contactsError("Failed to copy contact")
        }

        let saveRequest = CNSaveRequest()
        saveRequest.delete(mutable)
        do {
            try contactStore.execute(saveRequest)
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }
    }

    func updateContact(identifier: String, fields: [String: Any]) throws -> CNContact {
        guard let existing = try fetchContact(identifier: identifier) else {
            throw ContactsProviderError.invalidArguments("Unknown contact_identifier: \(identifier)")
        }

        guard let mutable = existing.mutableCopy() as? CNMutableContact else {
            throw ContactsProviderError.contactsError("Failed to copy contact")
        }

        try ContactsDeserialization.applyWritableFields(from: fields, to: mutable)

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutable)
        do {
            try contactStore.execute(saveRequest)
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }

        guard let saved = try fetchContact(identifier: identifier) else {
            throw ContactsProviderError.contactsError("Failed to fetch updated contact")
        }
        return saved
    }

    private func unifiedContacts(matching predicate: NSPredicate) throws -> [CNContact] {
        do {
            return try contactStore.unifiedContacts(
                matching: predicate,
                keysToFetch: ContactsKeyDescriptors.all
            )
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }
    }
}

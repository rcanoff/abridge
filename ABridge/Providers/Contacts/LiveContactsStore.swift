@preconcurrency import Contacts
import Foundation

@MainActor
final class LiveContactsStore: ContactsStoreing {
    let contactStore: CNContactStore
    private let contactLinking: any ContactsLinkingPerforming
    private let contactUnlinking: any ContactsUnlinkingPerforming

    init(
        contactStore: CNContactStore = CNContactStore(),
        contactLinking: any ContactsLinkingPerforming = LiveContactsLinkingPerformer(),
        contactUnlinking: any ContactsUnlinkingPerforming = LiveContactsUnlinkingPerformer()
    ) {
        self.contactStore = contactStore
        self.contactLinking = contactLinking
        self.contactUnlinking = contactUnlinking
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

    func updateGroup(identifier: String, fields: [String: Any]) throws -> CNGroup {
        guard let existing = try fetchGroup(identifier: identifier) else {
            throw ContactsProviderError.invalidArguments("Unknown group_identifier: \(identifier)")
        }

        guard let mutable = existing.mutableCopy() as? CNMutableGroup else {
            throw ContactsProviderError.contactsError("Failed to copy group")
        }

        try ContactsGroupDeserialization.applyWritableFields(from: fields, to: mutable)

        let saveRequest = CNSaveRequest()
        saveRequest.update(mutable)
        do {
            try contactStore.execute(saveRequest)
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }

        guard let saved = try fetchGroup(identifier: identifier) else {
            throw ContactsProviderError.contactsError("Failed to fetch updated group")
        }
        return saved
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

        let groups = try fetchGroups(containerIdentifier: containerIdentifier)
        guard let saved = groups.first(where: { $0.identifier == group.identifier }) else {
            throw ContactsProviderError.contactsError("Failed to fetch created group")
        }
        return saved
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
            throw ContactsSaveErrorMapping.map(error, wroteNote: !contact.note.isEmpty)
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

    func linkContacts(fromIdentifier: String, toIdentifier: String) throws -> CNContact {
        if fromIdentifier == toIdentifier {
            throw ContactsProviderError.invalidArguments(
                "from_contact_identifier and to_contact_identifier must differ"
            )
        }

        guard let fromContact = try fetchContact(identifier: fromIdentifier) else {
            throw ContactsProviderError.invalidArguments(
                "Unknown from_contact_identifier: \(fromIdentifier)"
            )
        }

        guard let toContact = try fetchContact(identifier: toIdentifier) else {
            throw ContactsProviderError.invalidArguments(
                "Unknown to_contact_identifier: \(toIdentifier)"
            )
        }

        guard let fromMutable = fromContact.mutableCopy() as? CNMutableContact,
              let toMutable = toContact.mutableCopy() as? CNMutableContact
        else {
            throw ContactsProviderError.contactsError("Failed to copy contact")
        }

        do {
            try executeLink(from: fromMutable, to: toMutable)
        } catch let error as ContactsProviderError {
            throw error
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }

        guard let linked = try fetchContact(identifier: toIdentifier) else {
            throw ContactsProviderError.contactsError("Failed to fetch linked contact")
        }
        return linked
    }

    func deleteGroup(identifier: String) throws {
        guard let existing = try fetchGroup(identifier: identifier) else {
            throw ContactsProviderError.invalidArguments("Unknown group_identifier: \(identifier)")
        }

        guard let mutable = existing.mutableCopy() as? CNMutableGroup else {
            throw ContactsProviderError.contactsError("Failed to copy group")
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
            throw ContactsSaveErrorMapping.map(
                error,
                wroteNote: fields.keys.contains("note")
            )
        }

        guard let saved = try fetchContact(identifier: identifier) else {
            throw ContactsProviderError.contactsError("Failed to fetch updated contact")
        }
        return saved
    }

    func unlinkContact(identifier: String) throws -> CNContact {
        guard let contact = try fetchContact(identifier: identifier) else {
            throw ContactsProviderError.invalidArguments("Unknown contact_identifier: \(identifier)")
        }

        guard let mutable = contact.mutableCopy() as? CNMutableContact else {
            throw ContactsProviderError.contactsError("Failed to copy contact")
        }

        do {
            try executeUnlink(mutable)
        } catch let error as ContactsProviderError {
            throw error
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }

        guard let unlinked = try fetchContact(identifier: identifier) else {
            throw ContactsProviderError.contactsError("Failed to fetch unlinked contact")
        }
        return unlinked
    }

    func executeLink(from fromMutable: CNMutableContact, to toMutable: CNMutableContact) throws {
        let saveRequest = CNSaveRequest()
        try contactLinking.link(from: fromMutable, to: toMutable, in: saveRequest)
        try contactStore.execute(saveRequest)
    }

    func executeUnlink(_ contactMutable: CNMutableContact) throws {
        let saveRequest = CNSaveRequest()
        try contactUnlinking.unlink(contactMutable, in: saveRequest)
        try contactStore.execute(saveRequest)
    }
}

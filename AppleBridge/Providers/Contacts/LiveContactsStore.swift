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

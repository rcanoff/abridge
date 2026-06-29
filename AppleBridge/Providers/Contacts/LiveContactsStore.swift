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
}
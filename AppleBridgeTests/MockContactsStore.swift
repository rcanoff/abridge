@testable import AppleBridge
import Contacts
import Foundation

@MainActor
final class MockContactsStore: ContactsStoreing {
    var authorizationStatus: CNAuthorizationStatus = .authorized
    var contacts: [CNContact] = []
    var knownContainerIdentifiers: Set<String> = ["container-1"]
    var fetchError: ContactsProviderError?

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
}
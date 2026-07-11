@preconcurrency import Contacts
import Foundation

extension LiveContactsStore {
    func fetchGroup(identifier: String) throws -> CNGroup? {
        do {
            let groups = try contactStore.groups(
                matching: CNGroup.predicateForGroups(withIdentifiers: [identifier])
            )
            return groups.first
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }
    }

    func unifiedContacts(matching predicate: NSPredicate) throws -> [CNContact] {
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

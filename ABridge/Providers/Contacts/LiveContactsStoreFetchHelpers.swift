@preconcurrency import Contacts
import Foundation

extension LiveContactsStore {
    func defaultContainerIdentifier() -> String {
        contactStore.defaultContainerIdentifier()
    }

    func listContainers() throws -> [ContactsContainerRecord] {
        let containers: [CNContainer]
        do {
            containers = try contactStore.containers(matching: nil)
        } catch {
            throw ContactsProviderError.contactsError(error.localizedDescription)
        }
        let defaultIdentifier = contactStore.defaultContainerIdentifier()
        return containers.map { container in
            ContactsContainerRecord(
                identifier: container.identifier,
                name: container.name,
                type: Self.containerTypeString(container.type),
                isDefault: container.identifier == defaultIdentifier
            )
        }
    }

    func containerIdentifiers(forContact identifier: String) -> [String] {
        let predicate = CNContainer.predicateForContainerOfContact(withIdentifier: identifier)
        guard let containers = try? contactStore.containers(matching: predicate) else {
            return []
        }
        return containers.map(\.identifier)
    }

    private static func containerTypeString(_ type: CNContainerType) -> String {
        switch type {
        case .local:
            "local"
        case .exchange:
            "exchange"
        case .cardDAV:
            "carddav"
        case .unassigned:
            "unassigned"
        @unknown default:
            "unknown"
        }
    }

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

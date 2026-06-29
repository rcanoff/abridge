@testable import AppleBridge
import Contacts
import Testing

@Suite("MockContactsStoreDelete")
struct MockContactsStoreDeleteTests {
    @Test
    @MainActor
    func deleteContactRemovesContactByIdentifier() throws {
        let store = MockContactsStore()
        let contact = ContactsTestSupport.makeRichContact()
        store.contacts = [contact]

        try store.deleteContact(identifier: contact.identifier)

        #expect(store.contacts.isEmpty)
        #expect(try store.fetchContact(identifier: contact.identifier) == nil)
    }

    @Test
    @MainActor
    func deleteContactRejectsUnknownIdentifier() {
        let store = MockContactsStore()

        #expect(throws: ContactsProviderError.self) {
            try store.deleteContact(identifier: "missing")
        }
    }

    @Test
    @MainActor
    func deleteGroupRemovesGroupByIdentifier() throws {
        let store = MockContactsStore()
        let group = ContactsTestSupport.makeGroup(name: "Family")
        store.groups = [group]

        try store.deleteGroup(identifier: group.identifier)

        #expect(store.groups.isEmpty)
    }

    @Test
    @MainActor
    func deleteGroupRejectsUnknownIdentifier() {
        let store = MockContactsStore()

        #expect(throws: ContactsProviderError.self) {
            try store.deleteGroup(identifier: "missing")
        }
    }
}

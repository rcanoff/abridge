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
}
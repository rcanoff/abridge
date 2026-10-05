@testable import ABridge
import Contacts
import Testing

@Suite("MockContactsStoreCreate")
struct MockContactsStoreCreateTests {
    @Test
    @MainActor
    func createContactAppendsContactWithGeneratedIdentifier() throws {
        let store = MockContactsStore()
        let contact = CNMutableContact()
        contact.givenName = "New"
        contact.familyName = "Person"

        let saved = try store.createContact(in: "container-1", contact: contact)

        #expect(saved.identifier.isEmpty == false)
        #expect(saved.givenName == "New")
        #expect(store.contacts.count == 1)
        #expect(try store.fetchContact(identifier: saved.identifier)?.givenName == "New")
    }

    @Test
    @MainActor
    func createContactRejectsUnknownContainer() {
        let store = MockContactsStore()
        let contact = CNMutableContact()
        contact.givenName = "New"

        #expect(throws: ContactsProviderError.self) {
            _ = try store.createContact(in: "missing", contact: contact)
        }
    }
}

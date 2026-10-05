@testable import ABridge
import Contacts
import Testing

@Suite("MockContactsStoreUnlink")
struct MockContactsStoreUnlinkTests {
    @Test
    @MainActor
    func unlinkContactReturnsContact() throws {
        let store = MockContactsStore()
        let contact = ContactsTestSupport.makeRichContact()
        store.contacts = [contact]

        let unlinked = try store.unlinkContact(identifier: contact.identifier)

        #expect(unlinked.identifier == contact.identifier)
        #expect(store.contacts.count == 1)
        #expect(store.contacts.first?.identifier == contact.identifier)
    }

    @Test
    @MainActor
    func unlinkContactRejectsUnknownIdentifier() {
        let store = MockContactsStore()

        #expect(throws: ContactsProviderError.self) {
            try store.unlinkContact(identifier: "missing-contact")
        }
    }

    @Test
    @MainActor
    func unlinkContactThrowsUnlinkingUnavailable() {
        let store = MockContactsStore()
        store.unlinkingUnavailable = true
        let contact = ContactsTestSupport.makeRichContact()
        store.contacts = [contact]

        #expect(throws: ContactsProviderError.unlinkingUnavailable) {
            try store.unlinkContact(identifier: contact.identifier)
        }
    }
}

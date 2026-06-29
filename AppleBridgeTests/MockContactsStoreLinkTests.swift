@testable import AppleBridge
import Contacts
import Testing

@Suite("MockContactsStoreLink")
struct MockContactsStoreLinkTests {
    @Test
    @MainActor
    func linkContactsRemovesFromContactAndReturnsDestination() throws {
        let store = MockContactsStore()
        let fromContact = ContactsTestSupport.makeRichContact()
        let toMutable = try #require(
            ContactsTestSupport.makeRichContact().mutableCopy() as? CNMutableContact
        )
        toMutable.givenName = "Destination"
        let toContact = toMutable as CNContact
        store.contacts = [fromContact, toContact]

        let linked = try store.linkContacts(
            fromIdentifier: fromContact.identifier,
            toIdentifier: toContact.identifier
        )

        #expect(linked.identifier == toContact.identifier)
        #expect(linked.givenName == "Destination")
        #expect(store.contacts.count == 1)
        #expect(store.contacts.first?.identifier == toContact.identifier)
        #expect(try store.fetchContact(identifier: fromContact.identifier) == nil)
    }

    @Test
    @MainActor
    func linkContactsRejectsUnknownFromIdentifier() {
        let store = MockContactsStore()
        let toContact = ContactsTestSupport.makeRichContact()
        store.contacts = [toContact]

        #expect(throws: ContactsProviderError.self) {
            try store.linkContacts(
                fromIdentifier: "missing-from",
                toIdentifier: toContact.identifier
            )
        }
    }

    @Test
    @MainActor
    func linkContactsRejectsUnknownToIdentifier() {
        let store = MockContactsStore()
        let fromContact = ContactsTestSupport.makeRichContact()
        store.contacts = [fromContact]

        #expect(throws: ContactsProviderError.self) {
            try store.linkContacts(
                fromIdentifier: fromContact.identifier,
                toIdentifier: "missing-to"
            )
        }
    }

    @Test
    @MainActor
    func linkContactsRejectsSameIdentifier() throws {
        let store = MockContactsStore()
        let contact = ContactsTestSupport.makeRichContact()
        store.contacts = [contact]

        #expect(throws: ContactsProviderError.self) {
            try store.linkContacts(
                fromIdentifier: contact.identifier,
                toIdentifier: contact.identifier
            )
        }
    }
}

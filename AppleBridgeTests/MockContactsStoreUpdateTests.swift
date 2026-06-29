@testable import AppleBridge
import Contacts
import Testing

@Suite("MockContactsStoreUpdate")
struct MockContactsStoreUpdateTests {
    @Test
    @MainActor
    func updateContactAppliesPartialFields() throws {
        let store = MockContactsStore()
        let contact = ContactsTestSupport.makeRichContact()
        store.contacts = [contact]

        let updated = try store.updateContact(
            identifier: contact.identifier,
            fields: ["given_name": "Janet", "note": NSNull()]
        )

        #expect(updated.givenName == "Janet")
        #expect(updated.familyName == "Doe")
        #expect(updated.note.isEmpty)
        #expect(try store.fetchContact(identifier: contact.identifier)?.givenName == "Janet")
    }

    @Test
    @MainActor
    func updateContactRejectsUnknownIdentifier() {
        let store = MockContactsStore()

        #expect(throws: ContactsProviderError.self) {
            _ = try store.updateContact(identifier: "missing", fields: ["given_name": "Jane"])
        }
    }
}
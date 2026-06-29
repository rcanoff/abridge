@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsSearchSupport")
struct ContactsSearchSupportTests {
    @Test
    func intersectContactsReturnsEmptyForNoSets() {
        #expect(ContactsSearchSupport.intersectContacts([]).isEmpty)
    }

    @Test
    func intersectContactsReturnsSingleSetUnchanged() {
        let contact = ContactsTestSupport.makeRichContact()
        let result = ContactsSearchSupport.intersectContacts([[contact]])

        #expect(result.count == 1)
        #expect(result.first?.identifier == contact.identifier)
    }

    @Test
    func intersectContactsKeepsContactsPresentInEverySet() {
        let sharedContact = ContactsTestSupport.makeRichContact()
        let otherContact = ContactsTestSupport.makeRichContact()
        let result = ContactsSearchSupport.intersectContacts([
            [sharedContact, otherContact],
            [sharedContact],
        ])

        #expect(result.count == 1)
        #expect(result.first?.identifier == sharedContact.identifier)
    }

    @Test
    func intersectContactsReturnsEmptyWhenSetsDoNotOverlap() {
        let firstContact = ContactsTestSupport.makeRichContact()
        let secondContact = ContactsTestSupport.makeRichContact()
        let result = ContactsSearchSupport.intersectContacts([[firstContact], [secondContact]])

        #expect(result.isEmpty)
    }
}

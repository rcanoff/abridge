@testable import AppleBridge
import Contacts
import Foundation
import Testing

private struct UnavailableContactsLinkingPerformer: ContactsLinkingPerforming {
    func link(
        from _: CNMutableContact,
        to _: CNMutableContact,
        in _: CNSaveRequest
    ) throws {
        throw ContactsProviderError.linkingUnavailable
    }
}

@Suite("LiveContactsStoreLink")
struct LiveContactsStoreLinkTests {
    @Test
    @MainActor
    func executeLinkThrowsLinkingUnavailableWhenPerformerReportsUnavailable() throws {
        let fromMutable = try #require(
            ContactsTestSupport.makeRichContact().mutableCopy() as? CNMutableContact
        )
        let toMutable = try #require(
            ContactsTestSupport.makeRichContact().mutableCopy() as? CNMutableContact
        )

        let store = LiveContactsStore(contactLinking: UnavailableContactsLinkingPerformer())

        #expect(throws: ContactsProviderError.linkingUnavailable) {
            try store.executeLink(from: fromMutable, to: toMutable)
        }
    }
}

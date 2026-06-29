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

    @Test
    func contactLinkingRuntimeSelectorIsAvailableOnSupportedMacOS() {
        // Verified on macOS 26: CNSaveRequest instances respond to linkContact:toContact:
        #expect(ContactsSaveRequestLinking.isAvailable == true)
    }

    @Test
    func liveLinkingPathCompletesWithoutCrashWhenRuntimeSupportsLinking() throws {
        let fromMutable = try #require(
            ContactsTestSupport.makeRichContact().mutableCopy() as? CNMutableContact
        )
        let toMutable = try #require(
            ContactsTestSupport.makeRichContact().mutableCopy() as? CNMutableContact
        )
        let saveRequest = CNSaveRequest()

        guard ContactsSaveRequestLinking.isAvailable else {
            #expect(throws: ContactsProviderError.linkingUnavailable) {
                try ContactsSaveRequestLinking.link(
                    from: fromMutable,
                    to: toMutable,
                    in: saveRequest
                )
            }
            return
        }

        // Typed BOOL objc_msgSend bridge must not trap on primitive YES/NO returns.
        #expect(ABContactLinkingIsAvailable())
        do {
            try ContactsSaveRequestLinking.link(from: fromMutable, to: toMutable, in: saveRequest)
        } catch let error as ContactsProviderError {
            #expect(error != .linkingUnavailable)
        }
    }
}

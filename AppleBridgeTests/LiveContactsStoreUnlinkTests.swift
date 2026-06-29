@testable import AppleBridge
import Contacts
import Foundation
import Testing

private struct UnavailableContactsUnlinkingPerformer: ContactsUnlinkingPerforming {
    func unlink(_: CNMutableContact, in _: CNSaveRequest) throws {
        throw ContactsProviderError.unlinkingUnavailable
    }
}

@Suite("LiveContactsStoreUnlink")
struct LiveContactsStoreUnlinkTests {
    @Test
    @MainActor
    func executeUnlinkThrowsUnlinkingUnavailableWhenPerformerReportsUnavailable() throws {
        let contactMutable = try #require(
            ContactsTestSupport.makeRichContact().mutableCopy() as? CNMutableContact
        )

        let store = LiveContactsStore(contactUnlinking: UnavailableContactsUnlinkingPerformer())

        #expect(throws: ContactsProviderError.unlinkingUnavailable) {
            try store.executeUnlink(contactMutable)
        }
    }

    @Test
    func contactUnlinkingRuntimeSelectorIsAvailableOnSupportedMacOS() {
        // Verified on macOS 26: CNSaveRequest instances respond to unlinkContact:
        #expect(ContactsSaveRequestUnlinking.isAvailable == true)
    }

    @Test
    func liveUnlinkingPathCompletesWithoutCrashWhenRuntimeSupportsUnlinking() throws {
        let contactMutable = try #require(
            ContactsTestSupport.makeRichContact().mutableCopy() as? CNMutableContact
        )
        let saveRequest = CNSaveRequest()

        guard ContactsSaveRequestUnlinking.isAvailable else {
            #expect(throws: ContactsProviderError.unlinkingUnavailable) {
                try ContactsSaveRequestUnlinking.unlink(contactMutable, in: saveRequest)
            }
            return
        }

        // Verified on macOS 26: unlinkContact: encoding is v24@0:8@16 (void).
        // Rejection surfaces via CNContactStore.execute.
        #expect(ABContactUnlinkingIsAvailable())
        do {
            try ContactsSaveRequestUnlinking.unlink(contactMutable, in: saveRequest)
        } catch let error as ContactsProviderError {
            #expect(error != .unlinkingUnavailable)
        }
    }
}

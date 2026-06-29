@testable import AppleBridge
import Testing

@Suite("LiveContactsStoreLink")
struct LiveContactsStoreLinkTests {
    @Test
    @MainActor
    func linkContactsThrowsLinkingUnavailable() {
        let store = LiveContactsStore()

        #expect(throws: ContactsProviderError.linkingUnavailable) {
            try store.linkContacts(fromIdentifier: "contact-from", toIdentifier: "contact-to")
        }
    }
}

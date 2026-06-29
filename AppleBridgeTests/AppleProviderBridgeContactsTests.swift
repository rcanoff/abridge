@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("AppleProviderBridgeContacts")
struct AppleProviderBridgeContactsTests {
    @Test
    @MainActor
    func callProviderContactsListContactsSucceedsWithMockStore() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        mockStore.contacts = [ContactsTestSupport.makeRichContact()]
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))

        let request = ProviderRequest(provider: "contacts", operation: "list_contacts", payloadJson: "{}")
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(decoded?.count == 1)
    }

    @Test
    @MainActor
    func callProviderContactsReturnsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))

        let request = ProviderRequest(provider: "contacts", operation: "list_contacts", payloadJson: "{}")
        let response = bridge.callProvider(request: request)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func callProviderContactsUnknownOperationWithQuoteProducesValidJSON() throws {
        let mockStore = MockContactsStore()
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))
        let operation = #"evil"operation"#
        let request = ProviderRequest(provider: "contacts", operation: operation, payloadJson: "{}")
        let response = bridge.callProvider(request: request)
        #expect(response.ok == false)

        let errorJson = try #require(response.errorJson)
        let data = try #require(errorJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["code"] as? String == "unknown_operation")
        #expect((decoded?["message"] as? String)?.contains(operation) == true)
    }
}

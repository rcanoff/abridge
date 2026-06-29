@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderSearchContacts")
struct ContactsProviderSearchContactsTests {
    @Test
    @MainActor
    func searchContactsReturnsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "search_contacts",
            payloadJson: #"{"name":"Jane"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func searchContactsRejectsMissingSearchCriteria() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(operation: "search_contacts", payloadJson: "{}")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("at least one search field required") == true)
    }

    @Test
    @MainActor
    func searchContactsRejectsAllNullSearchCriteria() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "search_contacts",
            payloadJson: #"{"name":null,"email_address":null,"phone_number":null}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("at least one search field required") == true)
    }

    @Test
    @MainActor
    func searchContactsSucceedsWithMockStore() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        mockStore.contacts = [ContactsTestSupport.makeRichContact()]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "search_contacts",
            payloadJson: #"{"name":"Jane","email_address":"jane@example.com"}"#
        )

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let contacts = try #require(decoded)
        #expect(contacts.count == 1)
        #expect(contacts.first?["given_name"] as? String == "Jane")
    }
}

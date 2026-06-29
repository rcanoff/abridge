@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderListContacts")
struct ContactsProviderListContactsTests {
    @Test
    @MainActor
    func listContactsReturnsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(operation: "list_contacts", payloadJson: "{}")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func listContactsSucceedsWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        mockStore.contacts = [ContactsTestSupport.makeRichContact()]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(operation: "list_contacts", payloadJson: "{}")

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("given_name"))
        #expect(response.payloadJson.contains("Jane"))
    }

    @Test
    @MainActor
    func listContactsReturnsJSONArrayOfContacts() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        mockStore.contacts = [ContactsTestSupport.makeRichContact()]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(operation: "list_contacts", payloadJson: "{}")

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let contacts = try #require(decoded)
        #expect(contacts.count == 1)
        #expect(contacts.first?["given_name"] as? String == "Jane")
    }

    @Test
    @MainActor
    func listContactsPassesContainerIdentifierToStore() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "list_contacts",
            payloadJson: #"{"container_identifier":"container-1"}"#
        )

        #expect(response.ok == true)
    }

    @Test
    @MainActor
    func listContactsRejectsUnknownContainerIdentifier() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "list_contacts",
            payloadJson: #"{"container_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func listContactsRejectsInvalidContainerIdentifierType() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "list_contacts",
            payloadJson: #"{"container_identifier":123}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }
}

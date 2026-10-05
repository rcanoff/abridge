@testable import ABridge
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
    func callProviderContactsUpdateContactSucceedsWithMockStore() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "contacts",
            operation: "update_contact",
            payloadJson: #"{"contact_identifier":"\#(contact.identifier)","given_name":"Updated"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["given_name"] as? String == "Updated")
    }

    @Test
    @MainActor
    func callProviderContactsLinkContactsSucceedsWithMockStore() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let fromContact = ContactsTestSupport.makeRichContact()
        let toContact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [fromContact, toContact]
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))

        let payloadJson = #"{"from_contact_identifier":"\#(fromContact.identifier)","#
            + #""to_contact_identifier":"\#(toContact.identifier)"}"#
        let request = ProviderRequest(
            provider: "contacts",
            operation: "link_contacts",
            payloadJson: payloadJson
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["identifier"] as? String == toContact.identifier)
        #expect(mockStore.contacts.count == 1)
    }

    @Test
    @MainActor
    func callProviderContactsUnlinkContactsSucceedsWithMockStore() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "contacts",
            operation: "unlink_contacts",
            payloadJson: #"{"contact_identifier":"\#(contact.identifier)"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["identifier"] as? String == contact.identifier)
        #expect(mockStore.contacts.count == 1)
    }

    @Test
    @MainActor
    func callProviderContactsDeleteContactSucceedsWithMockStore() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let contact = ContactsTestSupport.makeRichContact()
        mockStore.contacts = [contact]
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "contacts",
            operation: "delete_contact",
            payloadJson: #"{"contact_identifier":"\#(contact.identifier)"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"contact_identifier\":\"\(contact.identifier)\""))
        #expect(mockStore.contacts.isEmpty)
    }

    @Test
    @MainActor
    func callProviderContactsDeleteGroupSucceedsWithMockStore() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let group = ContactsTestSupport.makeGroup(name: "Family")
        mockStore.groups = [group]
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "contacts",
            operation: "delete_group",
            payloadJson: #"{"group_identifier":"\#(group.identifier)"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"group_identifier\":\"\(group.identifier)\""))
        #expect(mockStore.groups.isEmpty)
    }

    @Test
    @MainActor
    func callProviderContactsUpdateGroupSucceedsWithMockStore() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let group = ContactsTestSupport.makeGroup(name: "Family")
        mockStore.groups = [group]
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "contacts",
            operation: "update_group",
            payloadJson: #"{"group_identifier":"\#(group.identifier)","name":"Bridge Group"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["name"] as? String == "Bridge Group")
    }

    @Test
    @MainActor
    func callProviderContactsCreateGroupSucceedsWithMockStore() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "contacts",
            operation: "create_group",
            payloadJson: #"{"container_identifier":"container-1","name":"Bridge Group"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["name"] as? String == "Bridge Group")
    }

    @Test
    @MainActor
    func callProviderContactsCreateContactSucceedsWithMockStore() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let bridge = AppleProviderBridge(contactsProvider: ContactsProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "contacts",
            operation: "create_contact",
            payloadJson: #"{"container_identifier":"container-1","given_name":"Bridge"}"#
        )
        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["given_name"] as? String == "Bridge")
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

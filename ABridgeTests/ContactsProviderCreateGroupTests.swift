@testable import ABridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderCreateGroup")
struct ContactsProviderCreateGroupTests {
    private static let groupReadKeys: Set<String> = [
        "identifier",
        "name",
    ]

    @Test
    @MainActor
    func createGroupReturnsFaithfulPayload() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_group",
            payloadJson: #"{"container_identifier":"container-1","name":"Family"}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let group = try #require(decoded)

        #expect(Set(group.keys) == Self.groupReadKeys)
        #expect((group["identifier"] as? String)?.isEmpty == false)
        #expect(group["name"] as? String == "Family")
    }

    @Test
    @MainActor
    func createGroupUnknownContainerReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_group",
            payloadJson: #"{"container_identifier":"missing","name":"Family"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown container_identifier") == true)
        #expect(response.errorJson?.contains("contacts_list_containers") == true)
    }

    @Test
    @MainActor
    func createGroupUsesDefaultContainerWhenOmitted() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        mockStore.knownContainerIdentifiers = ["container-1", "icloud"]
        mockStore.defaultContainerIdentifierValue = "icloud"
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_group",
            payloadJson: #"{"name":"Family"}"#
        )

        #expect(response.ok == true)
        #expect(mockStore.groups.first?.name == "Family")
        #expect(mockStore.lastCreatedGroupContainerIdentifier == "icloud")
    }

    @Test
    @MainActor
    func createGroupPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_group",
            payloadJson: #"{"container_identifier":"container-1","name":"Family"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func createGroupPermissionDeniedWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_group",
            payloadJson: #"{"container_identifier":"container-1","name":"Family"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

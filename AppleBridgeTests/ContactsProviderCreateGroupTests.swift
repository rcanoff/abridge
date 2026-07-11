@testable import AppleBridge
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
    func createGroupMissingContainerIdentifierReturnsInvalidArguments_schemaOwnedByRust() {
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func createGroupMissingNameReturnsInvalidArguments_schemaOwnedByRust() {
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func createGroupWhitespaceOnlyNameReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_group",
            payloadJson: #"{"container_identifier":"container-1","name":"   "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("name must not be empty") == true)
    }

    @Test
    @MainActor
    func createGroupWhitespaceOnlyContainerReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_group",
            payloadJson: #"{"container_identifier":"   ","name":"Family"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("container_identifier must not be empty") == true)
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

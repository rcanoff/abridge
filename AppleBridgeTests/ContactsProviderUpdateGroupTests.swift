@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderUpdateGroup")
struct ContactsProviderUpdateGroupTests {
    private static let groupReadKeys: Set<String> = [
        "identifier",
        "name",
    ]

    @Test
    @MainActor
    func updateGroupReturnsFaithfulPayload() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let group = ContactsTestSupport.makeGroup(name: "Family")
        mockStore.groups = [group]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_group",
            payloadJson: #"{"group_identifier":"\#(group.identifier)","name":"Friends"}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let updated = try #require(decoded)

        #expect(Set(updated.keys) == Self.groupReadKeys)
        #expect(updated["identifier"] as? String == group.identifier)
        #expect(updated["name"] as? String == "Friends")
    }

    @Test
    @MainActor
    func updateGroupLeavesAbsentFieldsUnchanged() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let group = ContactsTestSupport.makeGroup(name: "Family")
        mockStore.groups = [group]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_group",
            payloadJson: #"{"group_identifier":"\#(group.identifier)"}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let updated = try #require(decoded)

        #expect(updated["name"] as? String == "Family")
    }

    @Test
    @MainActor
    func updateGroupClearsNameWithNull() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let group = ContactsTestSupport.makeGroup(name: "Family")
        mockStore.groups = [group]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_group",
            payloadJson: #"{"group_identifier":"\#(group.identifier)","name":null}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let updated = try #require(decoded)

        #expect(updated["name"] as? String == "")
    }

    @Test
    @MainActor
    func updateGroupMissingGroupIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_group",
            payloadJson: #"{"name":"Family"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("group_identifier is required") == true)
    }

    @Test
    @MainActor
    func updateGroupUnknownGroupIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_group",
            payloadJson: #"{"group_identifier":"missing","name":"Family"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown group_identifier") == true)
    }

    @Test
    @MainActor
    func updateGroupWhitespaceOnlyNameReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let group = ContactsTestSupport.makeGroup(name: "Family")
        mockStore.groups = [group]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_group",
            payloadJson: #"{"group_identifier":"\#(group.identifier)","name":"   "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("name must not be empty") == true)
    }

    @Test
    @MainActor
    func updateGroupPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_group",
            payloadJson: #"{"group_identifier":"group-1","name":"Family"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func updateGroupPermissionDeniedWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_group",
            payloadJson: #"{"group_identifier":"group-1","name":"Family"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}
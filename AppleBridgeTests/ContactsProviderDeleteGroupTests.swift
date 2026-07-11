@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderDeleteGroup")
struct ContactsProviderDeleteGroupTests {
    @Test
    @MainActor
    func deleteGroupReturnsIdentifierEnvelope() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let group = ContactsTestSupport.makeGroup(name: "Family")
        mockStore.groups = [group]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_group",
            payloadJson: #"{"group_identifier":"\#(group.identifier)"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"group_identifier\":\"\(group.identifier)\""))
        #expect(!response.payloadJson.contains("\"name\""))
        #expect(mockStore.groups.isEmpty)
    }

    @Test
    @MainActor
    func deleteGroupUnknownGroupIdentifierReturnsInvalidArguments() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_group",
            payloadJson: #"{"group_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown group_identifier") == true)
    }

    @Test
    @MainActor
    func deleteGroupMissingGroupIdentifierReturnsInvalidArguments_schemaOwnedByRust() {
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func deleteGroupPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_group",
            payloadJson: #"{"group_identifier":"group-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
        #expect(response.errorJson?.contains("Contacts write access not granted") == true)
    }

    @Test
    @MainActor
    func deleteGroupPermissionDeniedWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_group",
            payloadJson: #"{"group_identifier":"group-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("ContactsProviderListGroups")
struct ContactsProviderListGroupsTests {
    @Test
    @MainActor
    func listGroupsReturnsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .denied
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(operation: "list_groups", payloadJson: "{}")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func listGroupsSucceedsWithLimitedAuthorization() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = try #require(CNAuthorizationStatus(rawValue: 4))
        mockStore.groups = [ContactsTestSupport.makeGroup(name: "Family")]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(operation: "list_groups", payloadJson: "{}")

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Family"))
    }

    @Test
    @MainActor
    func listGroupsReturnsJSONArrayOfGroups() throws {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        mockStore.groups = [ContactsTestSupport.makeGroup(name: "Work")]
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(operation: "list_groups", payloadJson: "{}")

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        let groups = try #require(decoded)
        #expect(groups.count == 1)
        let keys = groups.first.map { Set($0.keys) }
        #expect(keys == Set(["identifier", "name"]))
        #expect(groups.first?["name"] as? String == "Work")
    }

    @Test
    @MainActor
    func listGroupsPassesContainerIdentifierToStore() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "list_groups",
            payloadJson: #"{"container_identifier":"container-1"}"#
        )

        #expect(response.ok == true)
        #expect(mockStore.lastFetchGroupsContainerIdentifier == "container-1")
    }

    @Test
    @MainActor
    func listGroupsRejectsUnknownContainerIdentifier() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "list_groups",
            payloadJson: #"{"container_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func listGroupsRejectsInvalidContainerIdentifierType() {
        let mockStore = MockContactsStore()
        mockStore.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mockStore)

        let response = provider.handle(
            operation: "list_groups",
            payloadJson: #"{"container_identifier":123}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }
}

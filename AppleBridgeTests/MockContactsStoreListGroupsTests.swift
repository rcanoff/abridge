@testable import AppleBridge
import Contacts
import Foundation
import Testing

@Suite("MockContactsStoreListGroups")
struct MockContactsStoreListGroupsTests {
    @Test
    @MainActor
    func fetchGroupsReturnsAllGroupsWhenContainerIdentifierOmitted() throws {
        let store = MockContactsStore()
        store.groups = [ContactsTestSupport.makeGroup(name: "Family")]

        let groups = try store.fetchGroups(containerIdentifier: nil)

        #expect(groups.count == 1)
        #expect(groups.first?.name == "Family")
    }

    @Test
    @MainActor
    func fetchGroupsAcceptsKnownContainerIdentifier() throws {
        let store = MockContactsStore()
        store.groups = [ContactsTestSupport.makeGroup(name: "Work")]

        let groups = try store.fetchGroups(containerIdentifier: "container-1")

        #expect(groups.count == 1)
        #expect(groups.first?.name == "Work")
    }

    @Test
    @MainActor
    func fetchGroupsRejectsUnknownContainerIdentifier() {
        let store = MockContactsStore()
        store.groups = [ContactsTestSupport.makeGroup(name: "Friends")]

        #expect(throws: ContactsProviderError.self) {
            try store.fetchGroups(containerIdentifier: "missing")
        }
    }

    @Test
    @MainActor
    func fetchGroupsPropagatesFetchError() {
        let store = MockContactsStore()
        store.fetchError = .contactsError("store unavailable")

        #expect(throws: ContactsProviderError.self) {
            try store.fetchGroups(containerIdentifier: nil)
        }
    }
}
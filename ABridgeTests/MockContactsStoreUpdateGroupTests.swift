@testable import ABridge
import Contacts
import Testing

@Suite("MockContactsStoreUpdateGroup")
struct MockContactsStoreUpdateGroupTests {
    @Test
    @MainActor
    func updateGroupAppliesNameWhenProvided() throws {
        let store = MockContactsStore()
        let group = ContactsTestSupport.makeGroup(name: "Family")
        store.groups = [group]

        let updated = try store.updateGroup(
            identifier: group.identifier,
            fields: ["name": "Friends"]
        )

        #expect(updated.name == "Friends")
        #expect(store.groups.first?.name == "Friends")
    }

    @Test
    @MainActor
    func updateGroupLeavesAbsentFieldsUnchanged() throws {
        let store = MockContactsStore()
        let group = ContactsTestSupport.makeGroup(name: "Family")
        store.groups = [group]

        let updated = try store.updateGroup(identifier: group.identifier, fields: [:])

        #expect(updated.name == "Family")
        #expect(store.groups.first?.name == "Family")
    }

    @Test
    @MainActor
    func updateGroupClearsNameWithNull() throws {
        let store = MockContactsStore()
        let group = ContactsTestSupport.makeGroup(name: "Family")
        store.groups = [group]

        let updated = try store.updateGroup(
            identifier: group.identifier,
            fields: ["name": NSNull()]
        )

        #expect(updated.name.isEmpty)
        #expect(store.groups.first?.name.isEmpty == true)
    }

    @Test
    @MainActor
    func updateGroupRejectsUnknownIdentifier() {
        let store = MockContactsStore()

        #expect(throws: ContactsProviderError.self) {
            _ = try store.updateGroup(identifier: "missing", fields: ["name": "Family"])
        }
    }
}

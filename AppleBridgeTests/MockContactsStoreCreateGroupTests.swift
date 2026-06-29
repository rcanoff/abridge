@testable import AppleBridge
import Contacts
import Testing

@Suite("MockContactsStoreCreateGroup")
struct MockContactsStoreCreateGroupTests {
    @Test
    @MainActor
    func createGroupAppendsGroupWithGeneratedIdentifier() throws {
        let store = MockContactsStore()

        let saved = try store.createGroup(in: "container-1", name: "Family")

        #expect(saved.identifier.isEmpty == false)
        #expect(saved.name == "Family")
        #expect(store.groups.count == 1)
        #expect(store.groups.first?.name == "Family")
    }

    @Test
    @MainActor
    func createGroupRejectsUnknownContainer() {
        let store = MockContactsStore()

        #expect(throws: ContactsProviderError.self) {
            _ = try store.createGroup(in: "missing", name: "Family")
        }
    }
}
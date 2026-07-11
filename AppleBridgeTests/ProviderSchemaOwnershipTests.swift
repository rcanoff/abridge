@testable import AppleBridge
import Foundation
import Testing

/// Phase B: pure schema shape is Rust-owned; Swift providers map Apple-side only.
@Suite("ProviderSchemaOwnership")
struct ProviderSchemaOwnershipTests {
    @Test
    @MainActor
    func createReminderDoesNotEmitPureSchemaRequiredTitle() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-1")]
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-1"}"#
        )
        #expect(response.errorJson?.contains("title is required") != true)
        #expect(response.errorJson?.contains("title must not be empty") != true)
    }

    @Test
    @MainActor
    func createGroupDoesNotEmitPureSchemaEmptyName() {
        let mock = MockContactsStore()
        mock.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mock)
        let response = provider.handle(
            operation: "create_group",
            payloadJson: #"{"container_identifier":"c1","name":"   "}"#
        )
        #expect(response.errorJson?.contains("name must not be empty") != true)
        #expect(response.errorJson?.contains("container_identifier must not be empty") != true)
    }

    @Test
    @MainActor
    func linkContactsDoesNotEmitPureSchemaEmptyFrom() {
        let mock = MockContactsStore()
        mock.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mock)
        let response = provider.handle(
            operation: "link_contacts",
            payloadJson: #"{"from_contact_identifier":"","to_contact_identifier":"b"}"#
        )
        #expect(response.errorJson?.contains("from_contact_identifier must not be empty") != true)
    }

    @Test
    @MainActor
    func listEventsDoesNotEmitPureSchemaRequiredStartDate() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(operation: "list_events", payloadJson: "{}")
        #expect(response.errorJson?.contains("start_date is required") != true)
        #expect(response.errorJson?.contains("end_date is required") != true)
    }

    @Test
    @MainActor
    func setEventAlarmsDoesNotEmitPureSchemaRequiredAlarmsKey() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(
            operation: "set_event_alarms",
            payloadJson: #"{"event_identifier":"e1"}"#
        )
        #expect(response.errorJson?.contains("alarms is required") != true)
    }

    @Test
    @MainActor
    func searchPlacesDoesNotEmitPureSchemaRequiredQuery() {
        let store = MockMapKitStore()
        let provider = MapKitProvider(store: store, locationGrantsReadAccess: { true })
        let response = provider.handle(operation: "search_places", payloadJson: "{}")
        #expect(response.errorJson?.contains("query is required") != true)
        #expect(response.errorJson?.contains("query must not be empty") != true)
    }

    @Test
    @MainActor
    func openNavigationDoesNotEmitPureSchemaRequiredSourceKey() {
        let store = MockMapKitStore()
        let provider = MapKitProvider(store: store, locationGrantsReadAccess: { true })
        let response = provider.handle(operation: "open_navigation", payloadJson: "{}")
        #expect(response.errorJson?.contains("\"source is required\"") != true)
        #expect(response.errorJson?.contains("source is required") != true)
    }

    @Test
    @MainActor
    func getEventStillFailsUnknownIdentifierAtRuntime() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(
            operation: "get_event",
            payloadJson: #"{"event_identifier":"does-not-exist"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
    }

    @Test
    @MainActor
    func moveReminderDoesNotEmitPureSchemaEmptyCalendar() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-1")]
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(
            operation: "move_reminder",
            payloadJson: #"{"calendar_item_identifier":"r1","calendar_identifier":""}"#
        )
        #expect(response.errorJson?.contains("calendar_identifier must not be empty") != true)
    }
}

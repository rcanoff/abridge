@testable import ABridge
import Foundation
import Testing

/// Phase B AC3: pure schema shape is Rust-owned. Offline `provider.handle` with schema-required
/// top-level keys omitted must not dual-validate those keys as pure-schema errors.
@Suite("ProviderSchemaOwnership")
struct ProviderSchemaOwnershipTests {
    /// Pure-schema dual-validation patterns for a **top-level** key only (not nested paths like
    /// `source.coordinate`).
    private func assertNoTopLevelPureSchemaDualValidation(
        _ response: ProviderResponse,
        keys: [String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let errorJson = response.errorJson else {
            return
        }
        for key in keys {
            let banned = [
                "\(key) is required",
                "\(key) must not be empty",
                "\(key) must be an array",
                "\(key) must be an object",
                "\(key) must be an array or null",
                "\(key) must be an object or null",
                "\(key) must be a string",
            ]
            for phrase in banned {
                #expect(
                    errorJson.contains(phrase) == false,
                    "unexpected pure-schema dual-validation for top-level '\(key)': \(phrase) in \(errorJson)",
                    sourceLocation: sourceLocation
                )
            }
        }
    }

    @Test
    @MainActor
    func createReminderMissingTitleDoesNotPureSchemaDualValidate() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-1")]
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-1"}"#
        )
        assertNoTopLevelPureSchemaDualValidation(response, keys: ["title", "calendar_identifier"])
    }

    @Test
    @MainActor
    func setEventAlarmsMissingAlarmsDoesNotPureSchemaDualValidate() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(
            operation: "set_event_alarms",
            payloadJson: #"{"event_identifier":"e1"}"#
        )
        assertNoTopLevelPureSchemaDualValidation(response, keys: ["alarms", "event_identifier"])
        // Missing alarms maps to empty list; unknown event is runtime.
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
    }

    @Test
    @MainActor
    func setReminderAlarmsMissingAlarmsDoesNotPureSchemaDualValidate() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(
            operation: "set_reminder_alarms",
            payloadJson: #"{"calendar_item_identifier":"r1"}"#
        )
        assertNoTopLevelPureSchemaDualValidation(response, keys: ["alarms", "calendar_item_identifier"])
    }

    @Test
    @MainActor
    func setEventRecurrenceMissingRulesDoesNotPureSchemaDualValidate() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(
            operation: "set_event_recurrence",
            payloadJson: #"{"event_identifier":"e1"}"#
        )
        assertNoTopLevelPureSchemaDualValidation(response, keys: ["recurrence_rules", "event_identifier"])
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
    }

    @Test
    @MainActor
    func setReminderRecurrenceMissingRulesDoesNotPureSchemaDualValidate() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(
            operation: "set_reminder_recurrence",
            payloadJson: #"{"calendar_item_identifier":"r1"}"#
        )
        assertNoTopLevelPureSchemaDualValidation(response, keys: ["recurrence_rules", "calendar_item_identifier"])
    }

    @Test
    @MainActor
    func openNavigationMissingSourceDoesNotPureSchemaDualValidateTopLevel() {
        let store = MockMapKitStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(operation: "open_navigation", payloadJson: "{}")
        assertNoTopLevelPureSchemaDualValidation(response, keys: ["source", "destination"])
        // Nested coordinate mapping may still fail — that is not top-level pure schema.
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("source must be an object") != true)
        #expect(response.errorJson?.contains("destination must be an object") != true)
    }

    @Test
    @MainActor
    func calculateRouteMissingEndpointsDoesNotPureSchemaDualValidateTopLevel() {
        let store = MockMapKitStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(operation: "calculate_route", payloadJson: "{}")
        assertNoTopLevelPureSchemaDualValidation(response, keys: ["source", "destination"])
        #expect(response.errorJson?.contains("source must be an object") != true)
    }

    @Test
    @MainActor
    func estimateTravelTimeMissingEndpointsDoesNotPureSchemaDualValidateTopLevel() {
        let store = MockMapKitStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(operation: "estimate_travel_time", payloadJson: "{}")
        assertNoTopLevelPureSchemaDualValidation(response, keys: ["source", "destination"])
        #expect(response.errorJson?.contains("source must be an object") != true)
    }

    @Test
    @MainActor
    func createGroupMissingNameDoesNotPureSchemaDualValidate() {
        let mock = MockContactsStore()
        mock.authorizationStatus = .authorized
        let provider = ContactsProvider(store: mock)
        let response = provider.handle(
            operation: "create_group",
            payloadJson: #"{"container_identifier":"c1"}"#
        )
        assertNoTopLevelPureSchemaDualValidation(response, keys: ["name", "container_identifier"])
    }

    @Test
    @MainActor
    func listEventsMissingDatesDoesNotPureSchemaDualValidate() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)
        let response = provider.handle(operation: "list_events", payloadJson: "{}")
        assertNoTopLevelPureSchemaDualValidation(response, keys: ["start_date", "end_date"])
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
}

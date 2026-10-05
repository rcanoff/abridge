@testable import ABridge
import Foundation
import Testing

@Suite("EventKitProviderDeleteEvent")
struct EventKitProviderDeleteEventTests {
    @MainActor
    private func providerWithEvent() -> (EventKitProvider, MockEventKitStore) {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-delete", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-delete-1",
                calendarIdentifier: "cal-delete",
                title: "Remove me"
            ),
        ]
        return (EventKitProvider(store: mockStore), mockStore)
    }

    @Test
    @MainActor
    func deleteEventReturnsSuccessEnvelope() {
        let (provider, mockStore) = providerWithEvent()

        let response = provider.handle(
            operation: "delete_event",
            payloadJson: #"{"event_identifier":"evt-evt-delete-1"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"event_identifier\":\"evt-evt-delete-1\""))
        #expect(!response.payloadJson.contains("\"deleted\""))
        #expect(!response.payloadJson.contains("\"calendar_item_identifier\""))
        #expect(mockStore.events.isEmpty)
    }

    @Test
    @MainActor
    func deleteEventUnknownIDReturnsInvalidArguments() {
        let (provider, mockStore) = providerWithEvent()

        let response = provider.handle(
            operation: "delete_event",
            payloadJson: #"{"event_identifier":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
        #expect(mockStore.events.count == 1)
    }

    @Test
    @MainActor
    func deleteEventRoundtripUsesCreateEventIdentifier() throws {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-delete-roundtrip", title: "Work"),
        ]
        let provider = EventKitProvider(store: mockStore)

        let createResponse = provider.handle(
            operation: "create_event",
            payloadJson: """
            {"calendar_identifier":"cal-delete-roundtrip","title":"Delete me",\
            "start_date":"2023-11-14T22:13:20Z","end_date":"2023-11-14T22:43:20Z"}
            """
        )
        #expect(createResponse.ok == true)

        let createData = try #require(createResponse.payloadJson.data(using: .utf8))
        let created = try #require(
            try JSONSerialization.jsonObject(with: createData) as? [String: Any]
        )
        let eventIdentifier = try #require(created["event_identifier"] as? String)

        let deleteResponse = provider.handle(
            operation: "delete_event",
            payloadJson: #"{"event_identifier":"\#(eventIdentifier)"}"#
        )

        #expect(deleteResponse.ok == true)
        #expect(deleteResponse.payloadJson.contains("\"event_identifier\":\"\(eventIdentifier)\""))
        #expect(mockStore.events.isEmpty)
    }

    @Test
    @MainActor
    func deleteEventPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_event",
            payloadJson: #"{"event_identifier":"evt-1"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

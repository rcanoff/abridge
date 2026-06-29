@testable import AppleBridge
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
    func deleteEventMissingEventIdentifierReturnsInvalidArguments() {
        let (provider, _) = providerWithEvent()

        let response = provider.handle(operation: "delete_event", payloadJson: #"{}"#)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("event_identifier is required") == true)
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

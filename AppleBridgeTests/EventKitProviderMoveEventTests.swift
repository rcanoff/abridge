@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderMoveEvent")
struct EventKitProviderMoveEventTests {
    @MainActor
    private func providerWithEvent() -> (EventKitProvider, MockEventKitStore) {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let sourceCalendar = mockStore.makeTestEventCalendar(
            calendarIdentifier: "cal-source",
            title: "Source"
        )
        let targetCalendar = mockStore.makeTestEventCalendar(
            calendarIdentifier: "cal-target",
            title: "Target"
        )
        mockStore.eventCalendarsList = [sourceCalendar, targetCalendar]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-move-1",
                calendarIdentifier: "cal-source",
                title: "Move me",
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600)
            ),
        ]
        return (EventKitProvider(store: mockStore), mockStore)
    }

    @Test
    @MainActor
    func moveEventReturnsFaithfulPayload() {
        let (provider, mockStore) = providerWithEvent()

        let response = provider.handle(
            operation: "move_event",
            payloadJson: #"{"event_identifier":"evt-evt-move-1","calendar_identifier":"cal-target"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("Move me"))
        #expect(response.payloadJson.contains("cal-target"))
        #expect(mockStore.events.count == 1)
        #expect(mockStore.events[0].calendar?.calendarIdentifier == "cal-target")
        #expect(mockStore.events[0].title == "Move me")
    }

    @Test
    @MainActor
    func moveEventUnknownIDReturnsInvalidArguments() {
        let (provider, mockStore) = providerWithEvent()

        let response = provider.handle(
            operation: "move_event",
            payloadJson: #"{"event_identifier":"missing","calendar_identifier":"cal-target"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
        #expect(mockStore.events.count == 1)
    }

    @Test
    @MainActor
    func moveEventUnknownCalendarReturnsInvalidArguments() {
        let (provider, mockStore) = providerWithEvent()

        let response = provider.handle(
            operation: "move_event",
            payloadJson: #"{"event_identifier":"evt-evt-move-1","calendar_identifier":"missing-cal"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier") == true)
        #expect(mockStore.events[0].calendar?.calendarIdentifier == "cal-source")
    }

    @Test
    @MainActor
    func moveEventPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "move_event",
            payloadJson: #"{"event_identifier":"evt-1","calendar_identifier":"cal-target"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

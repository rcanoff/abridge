@testable import AppleBridge
import Foundation
import Testing

@Suite("AppleProviderBridgeEvent")
struct AppleProviderBridgeEventTests {
    @Test
    @MainActor
    func routesEventKitGetEvent() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.events = [
            EventKitTestSupport.makeEvent(
                calendarItemIdentifier: "evt-1",
                calendarIdentifier: "cal-work",
                title: "Standup"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "get_event",
            payloadJson: #"{"event_identifier":"evt-evt-1"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"title\":\"Standup\""))
    }

    @Test
    @MainActor
    func routesEventKitCreateEvent() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            EventKitTestSupport.makeEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "create_event",
            payloadJson: """
            {"calendar_identifier":"cal-work","title":"Standup",\
            "start_date":"2023-11-14T22:13:20Z","end_date":"2023-11-14T22:43:20Z"}
            """
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"title\":\"Standup\""))
    }

    @Test
    @MainActor
    func routesEventKitUpdateEvent() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            EventKitTestSupport.makeEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            EventKitTestSupport.makeEvent(
                calendarItemIdentifier: "evt-1",
                calendarIdentifier: "cal-work",
                title: "Standup"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "update_event",
            payloadJson: #"{"event_identifier":"evt-evt-1","title":"Updated Standup"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"title\":\"Updated Standup\""))
    }

    @Test
    @MainActor
    func routesEventKitMoveEvent() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            EventKitTestSupport.makeEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
            EventKitTestSupport.makeEventCalendar(calendarIdentifier: "cal-personal", title: "Personal"),
        ]
        mockStore.events = [
            EventKitTestSupport.makeEvent(
                calendarItemIdentifier: "evt-1",
                calendarIdentifier: "cal-work",
                title: "Standup"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "move_event",
            payloadJson: #"{"event_identifier":"evt-evt-1","calendar_identifier":"cal-personal"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("cal-personal"))
        #expect(mockStore.events[0].calendar?.calendarIdentifier == "cal-personal")
    }

    @Test
    @MainActor
    func routesEventKitDeleteEvent() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            EventKitTestSupport.makeEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            EventKitTestSupport.makeEvent(
                calendarItemIdentifier: "evt-1",
                calendarIdentifier: "cal-work",
                title: "Gone"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "delete_event",
            payloadJson: #"{"event_identifier":"evt-evt-1"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"event_identifier\":\"evt-evt-1\""))
        #expect(!response.payloadJson.contains("\"deleted\""))
    }
}

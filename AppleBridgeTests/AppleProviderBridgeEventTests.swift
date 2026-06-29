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
            mockStore.makeTestEvent(
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
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
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
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
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
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-personal", title: "Personal"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
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
    func routesEventKitSetEventAlarms() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-1",
                calendarIdentifier: "cal-work",
                title: "Standup"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "set_event_alarms",
            payloadJson: #"{"event_identifier":"evt-evt-1","alarms":[{"relative_offset":-300}]}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("relative_offset"))
        #expect(mockStore.events[0].alarms?.count == 1)
    }

    @Test
    @MainActor
    func routesEventKitSetEventRecurrence() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-1",
                calendarIdentifier: "cal-work",
                title: "Standup"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "set_event_recurrence",
            payloadJson: #"{"event_identifier":"evt-evt-1","recurrence_rules":[{"frequency":"daily","interval":1}]}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("frequency"))
        #expect(mockStore.events[0].recurrenceRules?.count == 1)
    }

    @Test
    @MainActor
    func routesEventKitAcceptInvitation() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let event = mockStore.makeTestEvent(
            calendarItemIdentifier: "evt-1",
            calendarIdentifier: "cal-work",
            title: "Invite"
        )
        mockStore.invitationRespondableEventIDs = ["evt-1"]
        mockStore.events = [event]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "accept_invitation",
            payloadJson: #"{"event_identifier":"evt-evt-1"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(mockStore.acceptedInvitationEventIDs.contains("evt-1"))
    }

    @Test
    @MainActor
    func routesEventKitDeclineInvitation() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let event = mockStore.makeTestEvent(
            calendarItemIdentifier: "evt-1",
            calendarIdentifier: "cal-work",
            title: "Invite"
        )
        mockStore.invitationRespondableEventIDs = ["evt-1"]
        mockStore.events = [event]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "decline_invitation",
            payloadJson: #"{"event_identifier":"evt-evt-1"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(mockStore.declinedInvitationEventIDs.contains("evt-1"))
    }

    @Test
    @MainActor
    func routesEventKitDeleteEvent() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
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

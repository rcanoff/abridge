@testable import ABridge
import EventKit
import Foundation
import Testing

@Suite("EventKitProviderEventRecurrence")
struct EventKitProviderEventRecurrenceTests {
    @Test
    @MainActor
    func setEventRecurrenceReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-recurrence"),
        ]
        let event = mockStore.makeTestEvent(
            calendarItemIdentifier: "evt-recurrence-1",
            calendarIdentifier: "cal-recurrence",
            title: "Recurring event"
        )
        event.notes = "unchanged"
        mockStore.events = [event]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_event_recurrence",
            payloadJson: """
            {"event_identifier":"evt-evt-recurrence-1",\
            "recurrence_rules":[{"frequency":"daily","interval":2}]}
            """
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("Recurring event"))
        #expect(response.payloadJson.contains("unchanged"))
        #expect(response.payloadJson.contains("frequency"))
        #expect(mockStore.events.count == 1)
        #expect(mockStore.events[0].recurrenceRules?.count == 1)
        #expect(mockStore.events[0].recurrenceRules?.first?.frequency == .daily)
        #expect(mockStore.events[0].recurrenceRules?.first?.interval == 2)
    }

    @Test
    @MainActor
    func setEventRecurrenceEmptyArrayClearsRecurrenceRules() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-clear-recurrence"),
        ]
        let event = mockStore.makeTestEvent(
            calendarItemIdentifier: "evt-clear-recurrence-1",
            calendarIdentifier: "cal-clear-recurrence",
            title: "Clear recurrence"
        )
        event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]
        mockStore.events = [event]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_event_recurrence",
            payloadJson: #"{"event_identifier":"evt-evt-clear-recurrence-1","recurrence_rules":[]}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Clear recurrence"))
        #expect(mockStore.events.count == 1)
        #expect((mockStore.events[0].recurrenceRules ?? []).isEmpty)
    }

    @Test
    @MainActor
    func setEventRecurrenceUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_event_recurrence",
            payloadJson: #"{"event_identifier":"missing","recurrence_rules":[]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
    }

    @Test
    @MainActor
    func setEventRecurrencePermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_event_recurrence",
            payloadJson: #"{"event_identifier":"evt-1","recurrence_rules":[]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

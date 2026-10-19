@testable import ABridge
import EventKit
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

    @Test
    @MainActor
    func deleteEventByUniqueTitleRemovesThatEvent() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let start = Date(timeIntervalSinceNow: 86400)
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "standup",
                calendarIdentifier: "cal-work",
                title: "Standup",
                startDate: start,
                endDate: start.addingTimeInterval(1800)
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "delete_event",
            payloadJson: #"{"event_title":"standup"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("evt-standup"))
        #expect(mockStore.events.isEmpty)
        #expect(mockStore.lastEventSpan == .thisEvent)
    }

    @Test
    @MainActor
    func deleteEventByTitleTreatsOneSeriesAsOneEventAndRefusesDistinctTitles() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-home", title: "Home"),
        ]
        let soon = Date(timeIntervalSinceNow: 86400)
        let later = Date(timeIntervalSinceNow: 8 * 86400)
        let first = mockStore.makeTestEvent(
            calendarItemIdentifier: "series-a",
            calendarIdentifier: "cal-work",
            title: "Standup",
            startDate: soon,
            endDate: soon.addingTimeInterval(1800)
        )
        first.calendar?.title = "Work"
        first.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]
        let second = mockStore.makeTestEvent(
            calendarItemIdentifier: "series-b",
            calendarIdentifier: "cal-work",
            title: "Standup",
            startDate: later,
            endDate: later.addingTimeInterval(1800)
        )
        second.recurrenceRules = first.recurrenceRules
        let other = mockStore.makeTestEvent(
            calendarItemIdentifier: "home-1",
            calendarIdentifier: "cal-home",
            title: "standup",
            startDate: soon,
            endDate: soon.addingTimeInterval(1800)
        )
        other.calendar?.title = "Home"
        mockStore.eventIdentifierByItem = ["series-a": "series-standup", "series-b": "series-standup"]
        mockStore.events = [first, second, other]
        let provider = EventKitProvider(store: mockStore)

        let ambiguous = provider.handle(
            operation: "delete_event",
            payloadJson: #"{"event_title":"Standup"}"#
        )

        #expect(ambiguous.ok == false)
        #expect(ambiguous.errorJson?.contains("event_title_ambiguous") == true)
        #expect(ambiguous.errorJson?.contains("series-standup") == true)
        #expect(ambiguous.errorJson?.contains("evt-home-1") == true)
        #expect(ambiguous.errorJson?.contains("recurring yes") == true)
        #expect(ambiguous.errorJson?.contains("recurring no") == true)
        #expect(mockStore.events.count == 3)
    }

    @Test
    @MainActor
    func deleteOneOccurrenceLeavesTheRestOfTheSeries() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let soon = Date(timeIntervalSinceNow: 2 * 86400)
        let later = Date(timeIntervalSinceNow: 9 * 86400)
        let first = mockStore.makeTestEvent(
            calendarItemIdentifier: "occ-1",
            calendarIdentifier: "cal-work",
            title: "Standup",
            startDate: soon,
            endDate: soon.addingTimeInterval(1800)
        )
        let second = mockStore.makeTestEvent(
            calendarItemIdentifier: "occ-2",
            calendarIdentifier: "cal-work",
            title: "Standup",
            startDate: later,
            endDate: later.addingTimeInterval(1800)
        )
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        first.recurrenceRules = [rule]
        second.recurrenceRules = [rule]
        mockStore.eventIdentifierByItem = ["occ-1": "series-standup", "occ-2": "series-standup"]
        mockStore.events = [first, second]
        let provider = EventKitProvider(store: mockStore)

        let refused = provider.handle(
            operation: "delete_event",
            payloadJson: #"{"event_identifier":"series-standup"}"#
        )
        #expect(refused.ok == false)
        #expect(refused.errorJson?.contains("occurrence_required") == true)
        #expect(mockStore.events.count == 2)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        let occurrence = formatter.string(from: later)
        let deleted = provider.handle(
            operation: "delete_event",
            payloadJson: #"{"event_title":"Standup","occurrence_date":"\#(occurrence)","span":"this_event"}"#
        )
        #expect(deleted.ok == true, "\(deleted.errorJson ?? "")")
        #expect(mockStore.lastEventSpan == .thisEvent)
        #expect(mockStore.events.map(\.calendarItemIdentifier) == ["occ-1"])
    }
}

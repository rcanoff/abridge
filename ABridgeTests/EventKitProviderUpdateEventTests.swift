@testable import ABridge
import EventKit
import Foundation
import Testing

@Suite("EventKitProviderUpdateEvent")
struct EventKitProviderUpdateEventTests {
    private static let eventReadKeys: Set<String> = [
        "calendar_item_identifier",
        "calendar_item_external_identifier",
        "calendar",
        "title",
        "location",
        "url",
        "notes",
        "creation_date",
        "last_modified_date",
        "has_alarms",
        "has_recurrence_rules",
        "has_notes",
        "has_attendees",
        "time_zone",
        "attendees",
        "event_identifier",
        "availability",
        "start_date",
        "end_date",
        "is_all_day",
        "occurrence_date",
        "is_detached",
        "status",
        "birthday_contact_identifier",
        "organizer",
        "structured_location",
        "alarms",
        "recurrence_rules",
    ]

    @MainActor
    private func providerWithEvent(
        title: String = "Original title"
    ) -> (EventKitProvider, MockEventKitStore) {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-update-1",
                calendarIdentifier: "cal-work",
                title: title,
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600)
            ),
        ]
        return (EventKitProvider(store: mockStore), mockStore)
    }

    @Test
    @MainActor
    func updateEventReturnsFaithfulPayload() throws {
        let (provider, mockStore) = providerWithEvent()

        let response = provider.handle(
            operation: "update_event",
            payloadJson: #"{"event_identifier":"evt-evt-update-1","title":"Updated title"}"#
        )

        #expect(response.ok == true)
        #expect(mockStore.events.count == 1)
        #expect(mockStore.events[0].title == "Updated title")

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data)
        let event = try #require(decoded as? [String: Any])

        #expect(Set(event.keys) == Self.eventReadKeys)
        #expect(event["title"] as? String == "Updated title")
    }

    @Test
    @MainActor
    func updateEventAppliesOptionalFields() {
        let (provider, mockStore) = providerWithEvent()

        let response = provider.handle(
            operation: "update_event",
            payloadJson: """
            {"event_identifier":"evt-evt-update-1","notes":"Updated notes","location":"HQ",\
            "is_all_day":true,"availability":"busy"}
            """
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Updated notes"))
        #expect(response.payloadJson.contains("HQ"))
        #expect(response.payloadJson.contains("\"is_all_day\":true"))
        #expect(response.payloadJson.contains("\"availability\":\"not_supported\""))
        #expect(mockStore.events[0].notes == "Updated notes")
        #expect(mockStore.events[0].location == "HQ")
        #expect(mockStore.events[0].isAllDay == true)
    }

    @Test
    @MainActor
    func updateEventMovesCalendarWhenCalendarIdentifierProvided() {
        let (provider, mockStore) = providerWithEvent()
        let targetCalendar = mockStore.makeTestEventCalendar(
            calendarIdentifier: "cal-personal",
            title: "Personal"
        )
        mockStore.eventCalendarsList.append(targetCalendar)

        let response = provider.handle(
            operation: "update_event",
            payloadJson: #"{"event_identifier":"evt-evt-update-1","calendar_identifier":"cal-personal"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("cal-personal"))
        #expect(mockStore.events[0].calendar?.calendarIdentifier == "cal-personal")
    }

    @Test
    @MainActor
    func updateEventUnknownIDReturnsInvalidArguments() {
        let (provider, _) = providerWithEvent()

        let response = provider.handle(
            operation: "update_event",
            payloadJson: #"{"event_identifier":"missing","title":"Nope"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
    }

    @Test
    @MainActor
    func updateEventUnknownCalendarReturnsInvalidArguments() {
        let (provider, _) = providerWithEvent()

        let response = provider.handle(
            operation: "update_event",
            payloadJson: #"{"event_identifier":"evt-evt-update-1","calendar_identifier":"missing-cal"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_identifier") == true)
    }

    @Test
    @MainActor
    func updateEventStartAfterEndReturnsInvalidArguments() {
        let (provider, _) = providerWithEvent()

        let response = provider.handle(
            operation: "update_event",
            payloadJson: """
            {"event_identifier":"evt-evt-update-1",\
            "start_date":"2023-11-15T22:13:20Z","end_date":"2023-11-14T22:13:20Z"}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("start_date must not be after end_date") == true)
    }

    @Test
    @MainActor
    func updateEventPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_event",
            payloadJson: #"{"event_identifier":"evt-1","title":"Event"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func updateOneOccurrenceLeavesLaterOccurrences() {
        let series = weeklyStandupSeries()
        let mockStore = series.store
        let soon = series.soon
        let later = series.later
        let provider = EventKitProvider(store: mockStore)
        let thisOne = provider.handle(
            operation: "update_event",
            payloadJson: occurrenceUpdate("Moved", date: soon, span: "this_event")
        )
        #expect(thisOne.ok == true, "\(thisOne.errorJson ?? "")")
        #expect(mockStore.lastEventSpan == .thisEvent)
        #expect(mockStore.events[0].title == "Moved")
        #expect(mockStore.events[1].title == "Standup")

        let future = provider.handle(
            operation: "update_event",
            payloadJson: occurrenceUpdate("Rest", date: later, span: "future_events")
        )
        #expect(future.ok == true, "\(future.errorJson ?? "")")
        #expect(mockStore.lastEventSpan == .futureEvents)
        #expect(mockStore.events[1].title == "Rest")
        #expect(mockStore.events[0].title == "Moved")
    }

    private struct WeeklyStandup {
        let store: MockEventKitStore
        let soon: Date
        let later: Date
    }

    @MainActor
    private func weeklyStandupSeries() -> WeeklyStandup {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let soon = Date(timeIntervalSinceNow: 2 * 86400)
        let later = Date(timeIntervalSinceNow: 9 * 86400)
        let rule = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
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
        first.recurrenceRules = [rule]
        second.recurrenceRules = [rule]
        mockStore.eventIdentifierByItem = ["occ-1": "series-standup", "occ-2": "series-standup"]
        mockStore.events = [first, second]
        return WeeklyStandup(store: mockStore, soon: soon, later: later)
    }

    private func occurrenceUpdate(_ title: String, date: Date, span: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        let start = formatter.string(from: date)
        return """
        {"event_identifier":"series-standup","title":"\(title)",\
        "occurrence_date":"\(start)","span":"\(span)"}
        """
    }

    @Test
    @MainActor
    func updateRecurringEventWithoutOccurrenceDateChangesNothing() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        let start = Date(timeIntervalSinceNow: 3 * 86400)
        let event = mockStore.makeTestEvent(
            calendarItemIdentifier: "weekly",
            calendarIdentifier: "cal-work",
            title: "Standup",
            startDate: start,
            endDate: start.addingTimeInterval(1800)
        )
        event.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]
        mockStore.events = [event]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "update_event",
            payloadJson: #"{"event_identifier":"evt-weekly","title":"Nope"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("occurrence_required") == true)
        #expect(mockStore.events[0].title == "Standup")
        #expect(mockStore.lastEventSpan == nil)
    }
}

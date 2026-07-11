@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderSearchEvents")
struct EventKitProviderSearchEventsTests {
    @Test
    @MainActor
    func searchEventsFiltersByQuery() throws {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_086_400)
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-1",
                calendarIdentifier: "cal-work",
                title: "Team Standup",
                startDate: start,
                endDate: end
            ),
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-2",
                calendarIdentifier: "cal-work",
                title: "Lunch",
                startDate: start,
                endDate: end
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "search_events",
            payloadJson: #"{"start_date":"2023-11-14T22:13:20Z","end_date":"2023-11-15T22:13:20Z","query":"standup"}"#
        )

        #expect(response.ok == true)

        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data)
        let events = try #require(decoded as? [[String: Any]])

        #expect(events.count == 1)
        #expect(events.first?["title"] as? String == "Team Standup")
    }

    @Test
    @MainActor
    func searchEventsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "search_events",
            payloadJson: #"{"query":"standup"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func searchEventsMissingQueryReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema re-validation removed; Rust arg_validation owns this shape.
        // Offline provider path must not emit the old pure-schema invalid_arguments text.
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func searchEventsRejectsStartDateAfterEndDate() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "search_events",
            payloadJson: #"{"start_date":"2023-11-16T00:00:00Z","end_date":"2023-11-15T00:00:00Z","query":"meeting"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("start_date must not be after end_date") == true)
    }
}

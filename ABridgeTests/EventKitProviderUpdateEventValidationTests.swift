@testable import ABridge
import Foundation
import Testing

@Suite("EventKitProviderUpdateEventValidation")
struct EventKitUpdateEventValidationTests {
    @MainActor
    private func providerWithEvent() -> (EventKitProvider, MockEventKitStore) {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-work", title: "Work"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-val",
                calendarIdentifier: "cal-work",
                title: "Original",
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600)
            ),
        ]
        return (EventKitProvider(store: mockStore), mockStore)
    }

    @Test
    @MainActor
    func updateEventRejectsInvalidTimeZone() {
        let (provider, _) = providerWithEvent()

        let response = provider.handle(
            operation: "update_event",
            payloadJson: #"{"event_identifier":"evt-evt-val","time_zone":"Not/A/Zone"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("time_zone must be a valid timezone identifier") == true)
    }

    @Test
    @MainActor
    func updateEventRejectsInvalidAvailability() {
        let (provider, _) = providerWithEvent()

        let response = provider.handle(
            operation: "update_event",
            payloadJson: #"{"event_identifier":"evt-evt-val","availability":"maybe"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Invalid availability") == true)
    }

    @Test
    @MainActor
    func updateEventClearsNotesWhenNullProvided() {
        let (provider, mockStore) = providerWithEvent()
        mockStore.events[0].notes = "remove me"

        let response = provider.handle(
            operation: "update_event",
            payloadJson: #"{"event_identifier":"evt-evt-val","notes":null}"#
        )

        #expect(response.ok == true)
        #expect(mockStore.events[0].notes == nil)
    }

    @Test
    @MainActor
    func updateEventRejectsNullStartDate() {
        let (provider, _) = providerWithEvent()

        let response = provider.handle(
            operation: "update_event",
            payloadJson: #"{"event_identifier":"evt-evt-val","start_date":null}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("start_date must be an ISO8601 string") == true)
    }
}

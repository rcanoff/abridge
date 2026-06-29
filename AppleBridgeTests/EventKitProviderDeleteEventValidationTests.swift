@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderDeleteEventValidation")
struct EventKitDeleteEventValidationTests {
    @MainActor
    private func providerWithEvent() -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            EventKitTestSupport.makeEventCalendar(calendarIdentifier: "cal-val", title: "Work"),
        ]
        mockStore.events = [
            EventKitTestSupport.makeEvent(
                calendarItemIdentifier: "evt-val",
                calendarIdentifier: "cal-val",
                title: "Original"
            ),
        ]
        return EventKitProvider(store: mockStore)
    }

    @Test
    @MainActor
    func deleteEventRejectsEmptyEventIdentifier() {
        let provider = providerWithEvent()

        let response = provider.handle(
            operation: "delete_event",
            payloadJson: #"{"event_identifier":"   "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("event_identifier must not be empty") == true)
    }
}

@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderMoveEventValidation")
struct EventKitProviderMoveEventValidationTests {
    @MainActor
    private func providerWithEvent() -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            EventKitTestSupport.makeEventCalendar(calendarIdentifier: "cal-val", title: "Work"),
            EventKitTestSupport.makeEventCalendar(calendarIdentifier: "cal-other", title: "Personal"),
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
    func moveEventRejectsEmptyEventIdentifier() {
        let provider = providerWithEvent()

        let response = provider.handle(
            operation: "move_event",
            payloadJson: #"{"event_identifier":"   ","calendar_identifier":"cal-other"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("event_identifier must not be empty") == true)
    }

    @Test
    @MainActor
    func moveEventRejectsEmptyCalendarIdentifier() {
        let provider = providerWithEvent()

        let response = provider.handle(
            operation: "move_event",
            payloadJson: #"{"event_identifier":"evt-evt-val","calendar_identifier":"   "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_identifier must not be empty") == true)
    }
}

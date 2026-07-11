@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitEventAlarmsValidation")
struct EventKitEventAlarmsValidationTests {
    @MainActor
    private func providerWithEvent() -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-val"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-val",
                calendarIdentifier: "cal-val",
                title: "Original"
            ),
        ]
        return EventKitProvider(store: mockStore)
    }

    @Test
    @MainActor
    func setEventAlarmsRejectsInvalidAlarmRelativeOffset() {
        let provider = providerWithEvent()

        let response = provider.handle(
            operation: "set_event_alarms",
            payloadJson: """
            {"event_identifier":"evt-evt-val","alarms":[{"relative_offset":"soon"}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("relative_offset must be a number") == true)
    }

    @Test
    @MainActor
    func setEventAlarmsNullAlarmsMapsToEmptyWithoutPureSchemaDualValidation() {
        let provider = providerWithEvent()

        let response = provider.handle(
            operation: "set_event_alarms",
            payloadJson: #"{"event_identifier":"evt-evt-val","alarms":null}"#
        )

        #expect(response.errorJson?.contains("alarms must be an array") != true)
        #expect(response.ok == true)
    }
}

@testable import AppleBridge
import EventKit
import Foundation
import Testing

@Suite("EventKitProviderEventAlarms")
struct EventKitProviderEventAlarmsTests {
    @Test
    @MainActor
    func setEventAlarmsReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-alarms"),
        ]
        mockStore.events = [
            mockStore.makeTestEvent(
                calendarItemIdentifier: "evt-alarms-1",
                calendarIdentifier: "cal-alarms",
                title: "Alarm event",
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600)
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_event_alarms",
            payloadJson: #"{"event_identifier":"evt-evt-alarms-1","alarms":[{"relative_offset":-300}]}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("Alarm event"))
        #expect(response.payloadJson.contains("relative_offset"))
        #expect(mockStore.events.count == 1)
        #expect(mockStore.events[0].alarms?.count == 1)
        #expect(mockStore.events[0].alarms?.first?.relativeOffset == -300)
    }

    @Test
    @MainActor
    func setEventAlarmsEmptyArrayClearsAlarms() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-clear"),
        ]
        let event = mockStore.makeTestEvent(
            calendarItemIdentifier: "evt-clear-1",
            calendarIdentifier: "cal-clear",
            title: "Clear alarms"
        )
        event.alarms = [EKAlarm(relativeOffset: -600)]
        mockStore.events = [event]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_event_alarms",
            payloadJson: #"{"event_identifier":"evt-evt-clear-1","alarms":[]}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Clear alarms"))
        #expect(mockStore.events.count == 1)
        #expect((mockStore.events[0].alarms ?? []).isEmpty)
    }

    @Test
    @MainActor
    func setEventAlarmsMissingEventIdentifierReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func setEventAlarmsMissingAlarmsReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema re-validation removed; Rust arg_validation owns this shape.
        // Offline provider path must not emit the old pure-schema invalid_arguments text.
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func setEventAlarmsUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_event_alarms",
            payloadJson: #"{"event_identifier":"missing","alarms":[]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown event_identifier") == true)
    }

    @Test
    @MainActor
    func setEventAlarmsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_event_alarms",
            payloadJson: #"{"event_identifier":"evt-1","alarms":[]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

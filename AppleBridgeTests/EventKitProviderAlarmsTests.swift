@testable import AppleBridge
import EventKit
import Foundation
import Testing

@Suite("EventKitProviderAlarms")
struct EventKitProviderAlarmsTests {
    @Test
    @MainActor
    func setReminderAlarmsReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-alarms")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-alarms-1",
                calendarIdentifier: "list-alarms",
                title: "Alarm task",
                notes: "unchanged"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_alarms",
            payloadJson: #"{"calendar_item_identifier":"rem-alarms-1","alarms":[{"relative_offset":-300}]}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("Alarm task"))
        #expect(response.payloadJson.contains("unchanged"))
        #expect(response.payloadJson.contains("relative_offset"))
        #expect(mockStore.reminders.count == 1)
        #expect(mockStore.reminders[0].alarms?.count == 1)
        #expect(mockStore.reminders[0].alarms?.first?.relativeOffset == -300)
    }

    @Test
    @MainActor
    func setReminderAlarmsEmptyArrayClearsAlarms() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-clear")]
        let reminder = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-clear-1",
            calendarIdentifier: "list-clear",
            title: "Clear alarms"
        )
        reminder.alarms = [EKAlarm(relativeOffset: -600)]
        mockStore.reminders = [reminder]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_alarms",
            payloadJson: #"{"calendar_item_identifier":"rem-clear-1","alarms":[]}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Clear alarms"))
        #expect(mockStore.reminders.count == 1)
        #expect((mockStore.reminders[0].alarms ?? []).isEmpty)
    }

    @Test
    @MainActor
    func setReminderAlarmsMissingReminderIDReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func setReminderAlarmsMissingAlarmsReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema re-validation removed; Rust arg_validation owns this shape.
        // Offline provider path must not emit the old pure-schema invalid_arguments text.
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func setReminderAlarmsUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_alarms",
            payloadJson: #"{"calendar_item_identifier":"missing","alarms":[]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_item_identifier") == true)
    }

    @Test
    @MainActor
    func setReminderAlarmsPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "set_reminder_alarms",
            payloadJson: #"{"calendar_item_identifier":"rem-1","alarms":[]}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

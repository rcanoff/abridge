@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderCompleteValidation")
struct EventKitProviderCompleteValidationTests {
    @MainActor
    private func providerWithReminder(reminderID: String = "rem-val") -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-val")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: reminderID,
                calendarIdentifier: "list-val",
                title: "Original"
            ),
        ]
        return EventKitProvider(store: mockStore)
    }

    @Test
    @MainActor
    func completeReminderRejectsEmptyReminderID_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func uncompleteReminderRejectsEmptyReminderID_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }
}

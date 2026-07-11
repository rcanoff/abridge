@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderDeleteValidation")
struct EventKitProviderDeleteValidationTests {
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
}

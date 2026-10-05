@testable import ABridge
import Foundation
import Testing

@Suite("EventKitProviderDeleteEventValidation")
struct EventKitDeleteEventValidationTests {
    @MainActor
    private func providerWithEvent() -> EventKitProvider {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        mockStore.eventCalendarsList = [
            mockStore.makeTestEventCalendar(calendarIdentifier: "cal-val", title: "Work"),
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
}

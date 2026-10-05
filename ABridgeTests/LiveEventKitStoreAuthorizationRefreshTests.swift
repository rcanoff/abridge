@testable import ABridge
import EventKit
import Foundation
import Testing

@Suite("LiveEventKitStoreRefresh")
@MainActor
struct LiveEventKitStoreRefreshTests {
    @Test
    func recreatesEventStoreAfterEventAccessIsGranted() {
        var eventStatus: EKAuthorizationStatus = .notDetermined
        var created = 0
        let store = LiveEventKitStore(
            makeEventStore: {
                created += 1
                return EKEventStore()
            },
            reminderAuthorizationStatus: { .notDetermined },
            eventAuthorizationStatus: { eventStatus }
        )

        #expect(created == 1)
        _ = store.eventCalendars()
        #expect(created == 1)

        eventStatus = .fullAccess
        _ = store.eventCalendars()
        #expect(created == 2)

        _ = store.eventCalendars()
        #expect(created == 2)
    }

    @Test
    func recreatesEventStoreAfterReminderAccessIsGranted() {
        var reminderStatus: EKAuthorizationStatus = .notDetermined
        var created = 0
        let store = LiveEventKitStore(
            makeEventStore: {
                created += 1
                return EKEventStore()
            },
            reminderAuthorizationStatus: { reminderStatus },
            eventAuthorizationStatus: { .notDetermined }
        )

        _ = store.reminderCalendars()
        #expect(created == 1)

        reminderStatus = .fullAccess
        _ = store.reminderCalendars()
        #expect(created == 2)
    }
}

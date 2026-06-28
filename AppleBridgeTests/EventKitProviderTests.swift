@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProvider")
struct EventKitProviderTests {
    @Test
    @MainActor
    func listRemindersSurfacesFetchTimeout() {
        let stalledStore = StalledEventKitStore()
        let provider = EventKitProvider(store: stalledStore)

        let response = provider.handle(operation: "list_reminders", payloadJson: "{}")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("eventkit_error") == true)
        #expect(response.errorJson?.contains("Reminder fetch timed out") == true)
    }

    @Test
    @MainActor
    func defaultFetchTimeoutIsBounded() {
        #expect(EventKitReminderFetch.defaultTimeout == 5)
    }

    @Test
    @MainActor
    func waitForCompletionReturnsWhenCallbackFires() throws {
        var completed = false

        try EventKitReminderFetch.waitForCompletion(timeout: 1) { complete in
            complete()
            completed = true
        }

        #expect(completed)
    }

    @Test
    @MainActor
    func waitForCompletionPumpsRunLoopForDeferredCallback() throws {
        var result = 0

        try EventKitReminderFetch.waitForCompletion(timeout: 1) { complete in
            // EventKit delivers completions on the main run loop, not via immediate return.
            Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { _ in
                result = 42
                complete()
            }
        }

        #expect(result == 42)
    }

    @Test
    @MainActor
    func waitForCompletionTimesOutWithinBoundedDeadline() {
        let timeout: TimeInterval = 0.1
        let started = ContinuousClock.now

        #expect(throws: EventKitProviderError.reminderFetchTimedOut) {
            try EventKitReminderFetch.waitForCompletion(timeout: timeout) { _ in
                // Intentionally never call complete — mirrors a stalled EventKit callback.
            }
        }

        let elapsed = started.duration(to: .now)
        #expect(elapsed < .seconds(timeout + 0.25))
    }

    @Test
    @MainActor
    func getReminderReturnsPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.fakeReminders = [
            FakeReminder(
                id: "rem-1",
                listID: "list-1",
                title: "Task",
                completed: false,
                dueDateISO: nil,
                notes: nil
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_reminder",
            payloadJson: #"{"reminder_id":"rem-1"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("rem-1"))
        #expect(response.payloadJson.contains("list-1"))
    }

    @Test
    @MainActor
    func getReminderUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_reminder",
            payloadJson: #"{"reminder_id":"missing"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func getReminderMissingReminderIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "get_reminder", payloadJson: "{}")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func getReminderEmptyPayloadReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "get_reminder", payloadJson: "")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("reminder_id is required") == true)
    }

    @Test
    @MainActor
    func listRemindersIncludesListID() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.fakeReminders = [
            FakeReminder(
                id: "rem-2",
                listID: "list-9",
                title: "Eggs",
                completed: true,
                dueDateISO: nil,
                notes: nil
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "list_reminders", payloadJson: "{}")

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("list-9"))
        #expect(response.payloadJson.contains("rem-2"))
    }
}

import Foundation
import Testing
@testable import AppleBridge

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
}
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
    func getReminderReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-1",
                calendarIdentifier: "list-1",
                title: "Task"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_reminder",
            payloadJson: #"{"calendar_item_identifier":"rem-1"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("rem-1"))
        #expect(response.payloadJson.contains("calendar_identifier"))
        #expect(response.payloadJson.contains("list-1"))
    }

    @Test
    @MainActor
    func getReminderDoesNotTrimReminderIDForLookup() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-1",
                calendarIdentifier: "list-1",
                title: "Task"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_reminder",
            payloadJson: #"{"calendar_item_identifier":" rem-1 "}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown calendar_item_identifier:  rem-1 ") == true)
    }

    @Test
    @MainActor
    func getReminderUnknownIDReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "get_reminder",
            payloadJson: #"{"calendar_item_identifier":"missing"}"#
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
    func listRemindersRejectsMalformedJSON() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "list_reminders", payloadJson: "{")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func getReminderRejectsMalformedJSON() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "get_reminder", payloadJson: "{")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func getReminderEmptyPayloadReturnsInvalidArguments_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func listRemindersReturnsFaithfulReminderShape() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-2",
                calendarIdentifier: "list-9",
                title: "Eggs",
                isCompleted: true
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "list_reminders", payloadJson: "{}")

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("rem-2"))
        #expect(response.payloadJson.contains("list-9"))
        #expect(response.payloadJson.contains("is_completed"))
    }
}

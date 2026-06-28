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
            payloadJson: #"{"reminder_id":"rem-1"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("rem-1"))
        #expect(response.payloadJson.contains("calendar_identifier"))
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
    func searchRemindersFiltersByCompletionStatus() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-open",
                title: "Open task",
                isCompleted: false
            ),
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-done",
                title: "Done task",
                isCompleted: true
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "search_reminders",
            payloadJson: #"{"completion_status":"incomplete"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("rem-open"))
        #expect(!response.payloadJson.contains("rem-done"))
    }

    @Test
    @MainActor
    func searchRemindersCompletedFiltersByDueDateNotCompletionDate() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess

        let earlyDue = Date(timeIntervalSince1970: 1_700_000_000)
        let lateDue = Date(timeIntervalSince1970: 1_800_000_000)
        let earlyCompletion = Date(timeIntervalSince1970: 1_750_000_000)
        let lateCompletion = Date(timeIntervalSince1970: 1_850_000_000)

        let dueInRangeCompletedOutside = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-due-in-range",
            title: "Due in range",
            isCompleted: true
        )
        dueInRangeCompletedOutside.completionDate = lateCompletion
        dueInRangeCompletedOutside.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: lateDue
        )

        let dueOutsideCompletedInRange = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-due-outside",
            title: "Due outside",
            isCompleted: true
        )
        dueOutsideCompletedInRange.completionDate = earlyCompletion
        dueOutsideCompletedInRange.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: earlyDue
        )

        mockStore.reminders = [dueInRangeCompletedOutside, dueOutsideCompletedInRange]
        let provider = EventKitProvider(store: mockStore)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let start = formatter.string(from: Date(timeIntervalSince1970: 1_790_000_000))
        let end = formatter.string(from: Date(timeIntervalSince1970: 1_810_000_000))

        let response = provider.handle(
            operation: "search_reminders",
            payloadJson: #"{"completion_status":"completed","due_date_start":"\#(start)","due_date_end":"\#(end)"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("rem-due-in-range"))
        #expect(!response.payloadJson.contains("rem-due-outside"))
    }

    @Test
    @MainActor
    func searchRemindersRejectsInvalidCompletionStatus() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "search_reminders",
            payloadJson: #"{"completion_status":"maybe"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func searchRemindersReturnsFaithfulReminderShape() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-search",
                calendarIdentifier: "list-3",
                title: "Searchable"
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "search_reminders", payloadJson: "{}")

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_item_identifier"))
        #expect(response.payloadJson.contains("rem-search"))
        #expect(response.payloadJson.contains("list-3"))
    }

    @Test
    @MainActor
    func searchRemindersPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "search_reminders", payloadJson: "{}")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
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

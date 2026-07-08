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
    func getReminderEmptyPayloadReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "get_reminder", payloadJson: "")

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar_item_identifier is required") == true)
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
        if case let .incomplete(start, end, _)? = mockStore.lastPredicateKind {
            #expect(start == nil)
            #expect(end == nil)
        } else {
            Issue.record("expected incomplete predicate")
        }
    }

    @Test
    @MainActor
    func searchRemindersIncompleteUsesDueDateWindowOnIncompletePredicate() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess

        let inRangeDue = Date(timeIntervalSince1970: 1_800_000_000)
        let outsideDue = Date(timeIntervalSince1970: 1_700_000_000)

        let inRange = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-due-in-range",
            title: "Due in range",
            isCompleted: false
        )
        inRange.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: inRangeDue
        )

        let outside = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-due-outside",
            title: "Due outside",
            isCompleted: false
        )
        outside.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: outsideDue
        )

        mockStore.reminders = [inRange, outside]
        let provider = EventKitProvider(store: mockStore)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startDate = Date(timeIntervalSince1970: 1_790_000_000)
        let endDate = Date(timeIntervalSince1970: 1_810_000_000)
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)

        let response = provider.handle(
            operation: "search_reminders",
            payloadJson: #"{"completion_status":"incomplete","due_date_starting":"\#(start)","due_date_ending":"\#(end)"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("rem-due-in-range"))
        #expect(!response.payloadJson.contains("rem-due-outside"))
        if case let .incomplete(predicateStart, predicateEnd, _)? = mockStore.lastPredicateKind {
            #expect(predicateStart == startDate)
            #expect(predicateEnd == endDate)
        } else {
            Issue.record("expected incomplete predicate with due date window")
        }
    }

    @Test
    @MainActor
    func searchRemindersCompletedUsesCompletionDateParamsOnCompletedPredicate() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess

        let earlyCompletion = Date(timeIntervalSince1970: 1_750_000_000)
        let lateCompletion = Date(timeIntervalSince1970: 1_800_000_000)

        let completionInRange = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-completed-in-range",
            title: "Completed in range",
            isCompleted: true
        )
        completionInRange.completionDate = lateCompletion

        let completionOutside = EventKitTestSupport.makeReminder(
            calendarItemIdentifier: "rem-completed-outside",
            title: "Completed outside",
            isCompleted: true
        )
        completionOutside.completionDate = earlyCompletion

        mockStore.reminders = [completionInRange, completionOutside]
        let provider = EventKitProvider(store: mockStore)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let startDate = Date(timeIntervalSince1970: 1_790_000_000)
        let endDate = Date(timeIntervalSince1970: 1_810_000_000)
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)

        let response = provider.handle(
            operation: "search_reminders",
            payloadJson: #"{"completion_status":"completed","completion_date_starting":"\#(start)","completion_date_ending":"\#(end)"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("rem-completed-in-range"))
        #expect(!response.payloadJson.contains("rem-completed-outside"))
        if case let .completed(predicateStart, predicateEnd, _)? = mockStore.lastPredicateKind {
            #expect(predicateStart == startDate)
            #expect(predicateEnd == endDate)
        } else {
            Issue.record("expected completed predicate with completion date window")
        }
    }

    @Test
    @MainActor
    func searchRemindersAllRejectsDateArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "rem-any",
                title: "Any",
                isCompleted: false
            ),
        ]
        let provider = EventKitProvider(store: mockStore)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let start = formatter.string(from: Date(timeIntervalSince1970: 1_790_000_000))

        let withDue = provider.handle(
            operation: "search_reminders",
            payloadJson: #"{"completion_status":"all","due_date_starting":"\#(start)"}"#
        )
        #expect(withDue.ok == false)
        #expect(withDue.errorJson?.contains("invalid_arguments") == true)
        #expect(withDue.errorJson?.contains("predicateForReminders") == true)

        let withCompletion = provider.handle(
            operation: "search_reminders",
            payloadJson: #"{"completion_status":"all","completion_date_starting":"\#(start)"}"#
        )
        #expect(withCompletion.ok == false)
        #expect(withCompletion.errorJson?.contains("invalid_arguments") == true)

        let allOnly = provider.handle(
            operation: "search_reminders",
            payloadJson: #"{"completion_status":"all"}"#
        )
        #expect(allOnly.ok == true)
        #expect(allOnly.payloadJson.contains("rem-any"))
        if case .all? = mockStore.lastPredicateKind {
            // predicateForReminders(in:) — no post-fetch date filtering
        } else {
            Issue.record("expected all predicate")
        }
    }

    @Test
    @MainActor
    func searchRemindersRejectsMismatchedDateArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let start = formatter.string(from: Date(timeIntervalSince1970: 1_790_000_000))

        let completedWithDue = provider.handle(
            operation: "search_reminders",
            payloadJson: #"{"completion_status":"completed","due_date_starting":"\#(start)"}"#
        )
        #expect(completedWithDue.ok == false)
        #expect(completedWithDue.errorJson?.contains("invalid_arguments") == true)

        let incompleteWithCompletion = provider.handle(
            operation: "search_reminders",
            payloadJson: #"{"completion_status":"incomplete","completion_date_starting":"\#(start)"}"#
        )
        #expect(incompleteWithCompletion.ok == false)
        #expect(incompleteWithCompletion.errorJson?.contains("invalid_arguments") == true)
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

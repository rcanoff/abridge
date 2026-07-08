import EventKit
import Foundation
import Testing
@testable import AppleBridge

@Suite("EventKitProviderSearch")
struct EventKitProviderSearchTests {
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

        let payload =
            #"{"completion_status":"incomplete","due_date_starting":"\#(start)","due_date_ending":"\#(end)"}"#
        let response = provider.handle(
            operation: "search_reminders",
            payloadJson: payload
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

        let payload =
            #"{"completion_status":"completed","completion_date_starting":"\#(start)","completion_date_ending":"\#(end)"}"#
        let response = provider.handle(
            operation: "search_reminders",
            payloadJson: payload
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

}

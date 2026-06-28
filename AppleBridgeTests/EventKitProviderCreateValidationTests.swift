@testable import AppleBridge
import Foundation
import Testing

@Suite("EventKitProviderCreateValidation")
struct EventKitProviderCreateValidationTests {
    @Test
    @MainActor
    func createReminderRejectsBooleanPriority() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-5")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create-5","title":"Bool priority","priority":true}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsInvalidTimeZone() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-6")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create-6","title":"Bad tz","time_zone":"Not/A/Zone"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("time_zone must be a valid timezone identifier") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsInvalidDueDateComponentsTimeZone() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-7")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: """
            {"calendar_identifier":"list-create-7","title":"Bad nested tz",\
            "due_date_components":{"year":2026,"time_zone":"Not/A/Zone"}}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("time_zone must be a valid timezone identifier") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsInvalidDueDateComponentsCalendarIdentifier() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-8")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: """
            {"calendar_identifier":"list-create-8","title":"Bad calendar id",\
            "due_date_components":{"year":2026,"calendar":{"identifier":"not_a_calendar"}}}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("calendar identifier must be a valid calendar identifier") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsBooleanInRecurrenceNumberArray() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-9")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: """
            {"calendar_identifier":"list-create-9","title":"Bad recurrence",\
            "recurrence_rules":[{"frequency":"daily","days_of_the_month":[true]}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Expected integer in number array") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsFractionalPriority() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-10")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create-10","title":"Frac priority","priority":5.7}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsFractionalRecurrenceNumberArray() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-11")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: """
            {"calendar_identifier":"list-create-11","title":"Frac recurrence",\
            "recurrence_rules":[{"frequency":"daily","days_of_the_month":[5.7]}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Expected integer in number array") == true)
    }

    @Test
    @MainActor
    func createReminderPreservesWhitespaceInTitle() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-12")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create-12","title":"  Pay rent  "}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("  Pay rent  "))
    }

    @Test
    @MainActor
    func createReminderRejectsInvalidAlarmRelativeOffset() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-13")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: """
            {"calendar_identifier":"list-create-13","title":"Alarm test",\
            "alarms":[{"relative_offset":"soon"}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("relative_offset must be a number") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsInvalidStructuredLocationRadius() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-14")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: """
            {"calendar_identifier":"list-create-14","title":"Radius test",\
            "alarms":[{"structured_location":{"title":"Home","radius":true}}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("radius must be a number") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsNonPositiveRecurrenceOccurrenceCount() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-15")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: """
            {"calendar_identifier":"list-create-15","title":"Recurrence end",\
            "recurrence_rules":[{"frequency":"daily","recurrence_end":{"occurrence_count":0}}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("occurrence_count must be greater than 0") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsConflictingRecurrenceEndFields() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-16")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: """
            {"calendar_identifier":"list-create-16","title":"Recurrence conflict",\
            "recurrence_rules":[{"frequency":"daily","recurrence_end":{\
            "end_date":"2026-12-31T00:00:00Z","occurrence_count":5}}]}
            """
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("either end_date or occurrence_count") == true)
    }

    @Test
    @MainActor
    func createReminderRejectsInvalidPriority() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-create-4")]
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-create-4","title":"Bad priority","priority":10}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("priority must be between 0 and 9") == true)
    }
}

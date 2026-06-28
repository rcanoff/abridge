@testable import AppleBridge
import Foundation
import Testing

@Suite("AppleProviderBridge")
struct AppleProviderBridgeTests {
    @Test
    @MainActor
    func routesEventKitListCalendars() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .fullAccess
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_calendars",
            payloadJson: "{}"
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
    }

    @Test
    @MainActor
    func listCalendarsWriteOnlyAuthorizationIsInsufficientForRead() {
        let mockStore = MockEventKitStore()
        mockStore.eventAuthorizationStatusValue = .writeOnly
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_calendars",
            payloadJson: "{}"
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func routesEventKitListLists() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_lists",
            payloadJson: "{}"
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == true)
    }

    @Test
    @MainActor
    func writeOnlyAuthorizationIsInsufficientForRead() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .writeOnly
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_lists",
            payloadJson: "{}"
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func listRemindersRejectsInvalidListIDType() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))

        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_reminders",
            payloadJson: #"{"list_id":123}"#
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func routesEventKitCreateList() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "create_list",
            payloadJson: #"{"title":"New List"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("New List"))
    }

    @Test
    @MainActor
    func routesEventKitCreateReminder() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-new")]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "create_reminder",
            payloadJson: #"{"calendar_identifier":"list-new","title":"Created"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Created"))
    }

    @Test
    @MainActor
    func routesEventKitUpdateReminder() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-upd")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "r-upd",
                calendarIdentifier: "list-upd",
                title: "Before"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "update_reminder",
            payloadJson: #"{"reminder_id":"r-upd","title":"After"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("After"))
    }

    @Test
    @MainActor
    func routesEventKitMoveReminder() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let sourceList = mockStore.makeTestCalendar(calendarIdentifier: "list-src")
        let targetList = mockStore.makeTestCalendar(calendarIdentifier: "list-dst")
        mockStore.calendars = [sourceList, targetList]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "r-move",
                calendarIdentifier: "list-src",
                title: "Task"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "move_reminder",
            payloadJson: #"{"reminder_id":"r-move","calendar_identifier":"list-dst"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("list-dst"))
    }

    @Test
    @MainActor
    func routesEventKitCompleteReminder() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-done")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "r-done",
                calendarIdentifier: "list-done",
                title: "Task"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "complete_reminder",
            payloadJson: #"{"reminder_id":"r-done"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"is_completed\":true"))
    }

    @Test
    @MainActor
    func routesEventKitSetReminderAlarms() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-alarm")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "r-alarm",
                calendarIdentifier: "list-alarm",
                title: "Task"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "set_reminder_alarms",
            payloadJson: #"{"reminder_id":"r-alarm","alarms":[{"relative_offset":-300}]}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("relative_offset"))
    }

    @Test
    @MainActor
    func routesEventKitUncompleteReminder() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-reopen")]
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "r-reopen",
                calendarIdentifier: "list-reopen",
                title: "Done task",
                isCompleted: true
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "uncomplete_reminder",
            payloadJson: #"{"reminder_id":"r-reopen"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
        #expect(response.payloadJson.contains("\"is_completed\":false"))
    }

    @Test
    @MainActor
    func routesEventKitGetReminder() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        mockStore.reminders = [
            EventKitTestSupport.makeReminder(
                calendarItemIdentifier: "r1",
                calendarIdentifier: "l1",
                title: "T"
            ),
        ]
        let bridge = AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        let request = ProviderRequest(
            provider: "eventkit",
            operation: "get_reminder",
            payloadJson: #"{"reminder_id":"r1"}"#
        )
        let response = bridge.callProvider(request: request)
        #expect(response.ok == true)
    }

    @Test
    func unknownProviderReturnsError() {
        let bridge = AppleProviderBridge()
        let request = ProviderRequest(
            provider: "unknown",
            operation: "noop",
            payloadJson: "{}"
        )

        let response = bridge.callProvider(request: request)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("unknown_provider") == true)
    }

    @Test
    func callProviderEventKitFromDetachedThread() async {
        let bridge = await MainActor.run {
            let mockStore = MockEventKitStore()
            mockStore.authorizationStatus = .fullAccess
            return AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        }

        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_lists",
            payloadJson: "{}"
        )

        let response = await Task.detached {
            bridge.callProvider(request: request)
        }.value

        #expect(response.ok == true)
    }

    @Test
    func concurrentCallProviderEventKitFromDetachedThreads() async {
        let bridge = await MainActor.run {
            let mockStore = MockEventKitStore()
            mockStore.authorizationStatus = .fullAccess
            return AppleProviderBridge(eventKitProvider: EventKitProvider(store: mockStore))
        }

        let request = ProviderRequest(
            provider: "eventkit",
            operation: "list_lists",
            payloadJson: "{}"
        )

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    await Task.detached {
                        bridge.callProvider(request: request)
                    }.value.ok
                }
            }

            for await ok in group {
                #expect(ok == true)
            }
        }
    }

    @Test
    func unknownProviderFromDetachedThread() async {
        let bridge = AppleProviderBridge()
        let request = ProviderRequest(
            provider: "unknown",
            operation: "noop",
            payloadJson: "{}"
        )

        let response = await Task.detached {
            bridge.callProvider(request: request)
        }.value

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("unknown_provider") == true)
    }
}

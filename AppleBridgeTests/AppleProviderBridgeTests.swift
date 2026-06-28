@testable import AppleBridge
import Foundation
import Testing

@Suite("AppleProviderBridge")
struct AppleProviderBridgeTests {
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

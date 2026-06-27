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
}
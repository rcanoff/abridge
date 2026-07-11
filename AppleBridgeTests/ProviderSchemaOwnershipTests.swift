@testable import AppleBridge
import Foundation
import Testing

/// Phase B: pure schema shape is Rust-owned; Swift providers map Apple-side only.
@Suite("ProviderSchemaOwnership")
struct ProviderSchemaOwnershipTests {
    @Test
    func schemaTrustedPayloadDoesNotRequireKeys() {
        let value = SchemaTrustedPayload.requiredString([:], "title")
        #expect(value == "")
        let present = SchemaTrustedPayload.requiredString(["title": "Hello"], "title")
        #expect(present == "Hello")
    }

    @Test
    func createReminderNoLongerRejectsMissingTitleAsPureSchema() async {
        // Offline provider path: missing title is not re-validated as schema; mapping proceeds
        // (empty title). MCP path still rejects via Rust inputSchema.
        await MainActor.run {
            let mockStore = MockEventKitStore()
            mockStore.authorizationStatus = .fullAccess
            mockStore.calendars = [mockStore.makeTestCalendar(calendarIdentifier: "list-1")]
            let provider = EventKitProvider(store: mockStore)
            let response = provider.handle(
                operation: "create_reminder",
                payloadJson: #"{"calendar_identifier":"list-1"}"#
            )
            // Must not be the old pure-schema message.
            #expect(response.errorJson?.contains("title is required") != true)
            #expect(response.errorJson?.contains("title must not be empty") != true)
        }
    }

    @Test
    func searchPlacesNoLongerRejectsMissingQueryAsPureSchema() async {
        await MainActor.run {
            let store = MockMapKitStore()
            let provider = MapKitProvider(store: store, locationGrantsReadAccess: { true })
            let response = provider.handle(operation: "search_places", payloadJson: "{}")
            #expect(response.errorJson?.contains("query is required") != true)
            #expect(response.errorJson?.contains("query must not be empty") != true)
        }
    }

    @Test
    func getEventStillFailsUnknownIdentifierAtRuntime() async {
        await MainActor.run {
            let mockStore = MockEventKitStore()
            mockStore.authorizationStatus = .fullAccess
            let provider = EventKitProvider(store: mockStore)
            let response = provider.handle(
                operation: "get_event",
                payloadJson: #"{"event_identifier":"does-not-exist"}"#
            )
            #expect(response.ok == false)
            #expect(response.errorJson?.contains("Unknown event_identifier") == true)
        }
    }
}

@testable import AppleBridge
import CoreGraphics
import Foundation
import Testing

@Suite("EventKitProviderCreateList")
struct EventKitProviderCreateListTests {
    @Test
    @MainActor
    func createListReturnsFaithfulPayload() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_list",
            payloadJson: #"{"title":"Shopping"}"#
        )

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("calendar_identifier"))
        #expect(response.payloadJson.contains("Shopping"))
        #expect(mockStore.calendars.count == 1)
    }

    @Test
    @MainActor
    func createListAppliesOptionalFields() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let source = mockStore.defaultReminderSource()
        let provider = EventKitProvider(store: mockStore)

        let payloadJson = """
        {"title":"Colored List","source_identifier":"\(source?.sourceIdentifier ?? "")",\
        "cg_color":{"color_space_model":"rgb","components":[0.25,0.5,0.75,0.8],"alpha":0.8}}
        """
        let response = provider.handle(operation: "create_list", payloadJson: payloadJson)

        #expect(response.ok == true)
        #expect(response.payloadJson.contains("Colored List"))
        #expect(response.payloadJson.contains("cg_color"))
        #expect(response.payloadJson.contains("source"))
    }

    @Test
    @MainActor
    func createListMissingTitleReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "create_list", payloadJson: #"{}"#)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("title is required") == true)
    }

    @Test
    @MainActor
    func createListEmptyTitleReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(operation: "create_list", payloadJson: #"{"title":"   "}"#)

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("title must not be empty") == true)
    }

    @Test
    @MainActor
    func createListUnknownSourceIdentifierReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_list",
            payloadJson: #"{"title":"Bad Source","source_identifier":"missing-source"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("Unknown source_identifier") == true)
    }

    @Test
    @MainActor
    func createListInvalidCGColorReturnsInvalidArguments() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .fullAccess
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_list",
            payloadJson: #"{"title":"Bad Color","cg_color":{"color_space_model":"rgb","components":[0.25,0.5]}}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("cg_color components for rgb must have 3 or 4 values") == true)
        #expect(mockStore.calendars.isEmpty)
    }

    @Test
    @MainActor
    func createListPermissionDeniedWhenUnauthorized() {
        let mockStore = MockEventKitStore()
        mockStore.authorizationStatus = .denied
        let provider = EventKitProvider(store: mockStore)

        let response = provider.handle(
            operation: "create_list",
            payloadJson: #"{"title":"Shopping"}"#
        )

        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }
}

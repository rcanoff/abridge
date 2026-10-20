@testable import ABridge
import Foundation
import Testing

@Suite("MapKitProviderOpenNavigation")
struct MapKitProviderOpenNavigationTests {
    private let directionsURL =
        "https://maps.apple.com/directions?source=28.8028,-81.6445&waypoint=28.8653,-82.0401" +
        "&destination=27.9506,-82.4572&mode=driving&avoid=tolls"

    @Test
    @MainActor
    func openNavigationRefusesNonAppleMapsHostWithoutCallingStore() {
        let store = MockMapKitStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "open_navigation",
            payloadJson: #"{"url":"https://maps.google.com/directions?destination=1,2"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(store.lastOpenNavigationURL == nil)
    }

    @Test
    @MainActor
    func openNavigationRefusesNonHTTPSWithoutCallingStore() {
        let store = MockMapKitStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "open_navigation",
            payloadJson: #"{"url":"http://maps.apple.com/directions"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(store.lastOpenNavigationURL == nil)
    }

    @Test
    @MainActor
    func openNavigationRefusesNonDirectionsPathWithoutCallingStore() {
        let store = MockMapKitStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "open_navigation",
            payloadJson: #"{"url":"https://maps.apple.com/place?address=Cupertino"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(store.lastOpenNavigationURL == nil)
    }

    @Test
    @MainActor
    func openNavigationRefusesMissingURLWithoutCallingStore() {
        let store = MockMapKitStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(operation: "open_navigation", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(store.lastOpenNavigationURL == nil)
    }

    @Test
    @MainActor
    func openNavigationPassesValidURLUnchangedAndReportsOpened() throws {
        let store = MockMapKitStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "open_navigation",
            payloadJson: #"{"url":"\#(directionsURL)"}"#
        )

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["opened"] as? Bool == true)
        #expect(decoded?.count == 1)
        #expect(store.lastOpenNavigationURL?.absoluteString == directionsURL)
    }
}

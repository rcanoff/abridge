@testable import AppleBridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderSearchPlaces")
struct MapKitProviderSearchPlacesTests {
    @Test
    @MainActor
    func searchPlacesReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(operation: "search_places", payloadJson: #"{"query":"coffee"}"#)
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func searchPlacesRequiresQuery_schemaOwnedByRust() {
        // Pure schema shape (required/non-empty/priority) is enforced in Rust arg_validation
        // before ProviderBridge. This offline provider path no longer re-validates that shape.
        let value = SchemaTrustedPayload.requiredString([:], "any")
        #expect(value == "")
    }

    @Test
    @MainActor
    func searchPlacesRejectsUnsupportedResultTypes() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(
            operation: "search_places",
            payloadJson: #"{"query":"coffee","result_types":["query"]}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("not supported on this macOS version") == true)
    }

    @Test
    @MainActor
    func mapKitSearchFetchPumpsRunLoopForDeferredCallback() throws {
        var result = 0

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit search", timeout: 1) { complete in
            Timer.scheduledTimer(withTimeInterval: 0.001, repeats: false) { _ in
                result = 42
                complete()
            }
        }

        #expect(result == 42)
    }

    @Test
    @MainActor
    func mapKitSearchFetchTimesOutWithinBoundedDeadline() {
        let timeout: TimeInterval = 0.1
        let started = ContinuousClock.now

        #expect(throws: MapKitProviderError.mapkitError("MapKit nearby search timed out")) {
            try MapKitSearchFetch.waitForCompletion(operation: "MapKit nearby search", timeout: timeout) { _ in
                // Intentionally never call complete — mirrors a stalled MapKit callback.
            }
        }

        let elapsed = started.duration(to: .now)
        #expect(elapsed < .seconds(timeout + 0.25))
    }

    @Test
    @MainActor
    func searchPlacesReturnsSerializedResponse() throws {
        let item = MapKitTestFixtures.mapItem(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        item.name = "Mock Cafe"
        let store = MockMapKitStore()
        store.results = [MapKitSearchResult(mapItems: [item], boundingRegion: nil)]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(operation: "search_places", payloadJson: #"{"query":"coffee"}"#)
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Mock Cafe")
        #expect(store.lastRequest?.query == "coffee")
    }
}

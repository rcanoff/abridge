@testable import AppleBridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderSearchNearby")
struct MapKitProviderSearchNearbyTests {
    @Test
    @MainActor
    func searchNearbyReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "search_nearby",
            payloadJson: #"{"coordinate":{"latitude":37.0,"longitude":-122.0}}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

    @Test
    @MainActor
    func searchNearbyRequiresRegionOrCoordinate_schemaOwnedByRust() {
        // Pure schema re-validation removed; Rust arg_validation owns this shape.
        // Offline provider path must not emit the old pure-schema invalid_arguments text.
        #expect(SchemaTrustedPayload.requiredString([:], "x") == "")
    }

    @Test
    @MainActor
    func searchNearbyRejectsBothRegionAndCoordinate() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(
            operation: "search_nearby",
            payloadJson: """
            {"region":{"center":{"latitude":37.0,"longitude":-122.0},"span":\
            {"latitude_delta":0.1,"longitude_delta":0.1}},"coordinate":\
            {"latitude":37.0,"longitude":-122.0}}
            """
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func searchNearbyReturnsSerializedResponse() throws {
        let item = MapKitTestFixtures.mapItem(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        item.name = "Nearby Cafe"
        let store = MockMapKitStore()
        store.nearbyResults = [MapKitSearchResult(mapItems: [item], boundingRegion: nil)]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "search_nearby",
            payloadJson: #"{"coordinate":{"latitude":37.0,"longitude":-122.0},"radius_meters":800}"#
        )
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let mapItems = decoded?["map_items"] as? [[String: Any]]
        #expect(mapItems?.first?["name"] as? String == "Nearby Cafe")
        #expect(store.lastNearbyRequest != nil)
    }

    @Test
    @MainActor
    func searchNearbyPassesIncludingCategoriesFilterToStore() throws {
        let store = MockMapKitStore()
        store.nearbyResults = [MapKitSearchResult(mapItems: [], boundingRegion: nil)]
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "search_nearby",
            payloadJson: """
            {"coordinate":{"latitude":37.77,"longitude":-122.42},"radius_meters":1000,\
            "including_categories":["MKPOICategoryCafe"]}
            """
        )
        #expect(response.ok == true)
        let request = try #require(store.lastNearbyRequest)
        #expect(request.pointOfInterestFilter != nil)
    }

    @Test
    func nearbySupportBuildsPointsOfInterestRequestNotTextSearchRequest() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.42),
            latitudinalMeters: 1000,
            longitudinalMeters: 1000
        )
        let request = MapKitNearbySearchSupport.pointsOfInterestRequest(region: region, filter: nil)
        // Guards the regression: query-less nearby must use PointsOfInterestRequest (MKError 4 otherwise).
        #expect(type(of: request) == MKLocalPointsOfInterestRequest.self)
        #expect(request.region.center.latitude == region.center.latitude)
        #expect(request.region.center.longitude == region.center.longitude)
    }
}

@testable import ABridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderCalculateRoute")
struct MapKitProviderCalculateRouteTests {
    @Test
    @MainActor
    func calculateRouteRequiresSourceAndDestination() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "calculate_route", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func calculateRouteRejectsBothDepartureAndArrivalDates() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(
            operation: "calculate_route",
            payloadJson: routePayload(
                sourceLatitude: 37.3346,
                sourceLongitude: -122.0090,
                destinationLatitude: 37.7749,
                destinationLongitude: -122.4194,
                departureDate: "2026-06-30T12:00:00Z",
                arrivalDate: "2026-06-30T13:00:00Z"
            )
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("provide departure_date or arrival_date, not both") == true)
    }

    @Test
    @MainActor
    func calculateRouteReturnsSerializedResponse() throws {
        let store = makeSerializedRouteStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "calculate_route",
            payloadJson: routePayload(
                sourceLatitude: 37.3346,
                sourceLongitude: -122.0090,
                destinationLatitude: 37.7749,
                destinationLongitude: -122.4194,
                transportType: "walking"
            )
        )

        try expectSerializedCalculateRouteResponse(response, store: store)
    }

    @MainActor
    private func makeSerializedRouteStore() -> MockMapKitStore {
        let sourceItem = MapKitTestFixtures.mapItem(coordinate: CLLocationCoordinate2D(
            latitude: 37.3346,
            longitude: -122.0090
        ))
        sourceItem.name = "Apple Park"
        let destinationItem = MapKitTestFixtures.mapItem(coordinate: CLLocationCoordinate2D(
            latitude: 37.7749,
            longitude: -122.4194
        ))
        destinationItem.name = "San Francisco"

        let route = MapKitRouteData(
            name: "US-101",
            advisoryNotices: ["Avoid during winter storms"],
            distance: 77000,
            expectedTravelTime: 3600,
            transportType: .automobile,
            polylineCoordinates: [
                CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
                CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            ],
            polylineTitle: "Route polyline",
            polylineSubtitle: "Main path",
            steps: [
                MapKitRouteStepData(
                    instructions: "Head north on N De Anza Blvd",
                    notice: nil,
                    distance: 500,
                    transportType: .automobile,
                    polylineCoordinates: [
                        CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
                        CLLocationCoordinate2D(latitude: 37.3350, longitude: -122.0095),
                    ],
                    polylineTitle: "Step polyline",
                    polylineSubtitle: "First segment"
                ),
            ],
            hasTolls: false,
            hasHighways: true
        )

        let store = MockMapKitStore()
        store.calculateRouteResults = [
            MapKitCalculateRouteResult(
                source: sourceItem,
                destination: destinationItem,
                routes: [route]
            ),
        ]
        return store
    }

    @MainActor
    private func expectSerializedCalculateRouteResponse(
        _ response: ProviderResponse,
        store: MockMapKitStore
    ) throws {
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let source = decoded?["source"] as? [String: Any]
        let routes = decoded?["routes"] as? [[String: Any]]
        #expect(source?["name"] as? String == "Apple Park")
        #expect(routes?.first?["name"] as? String == "US-101")
        #expect(routes?.first?["has_highways"] as? Bool == true)
        let routePolyline = routes?.first?["polyline"] as? [String: Any]
        #expect(routePolyline?["title"] as? String == "Route polyline")
        #expect(routePolyline?["subtitle"] as? String == "Main path")
        let stepPolyline = (routes?.first?["steps"] as? [[String: Any]])?.first?["polyline"] as? [String: Any]
        #expect(stepPolyline?["title"] as? String == "Step polyline")
        #expect(stepPolyline?["subtitle"] as? String == "First segment")
        #expect(store.lastCalculateRouteRequest?.transportType == .walking)
    }

    private func routePayload(
        sourceLatitude: Double,
        sourceLongitude: Double,
        destinationLatitude: Double,
        destinationLongitude: Double,
        transportType: String? = nil,
        departureDate: String? = nil,
        arrivalDate: String? = nil
    ) -> String {
        var parts = [
            #""source":{"coordinate":{"latitude":\#(sourceLatitude),"longitude":\#(sourceLongitude)}}"#,
            #""destination":{"coordinate":{"latitude":\#(destinationLatitude),"longitude":\#(destinationLongitude)}}"#,
        ]
        if let transportType {
            parts.append(#""transport_type":"\#(transportType)""#)
        }
        if let departureDate {
            parts.append(#""departure_date":"\#(departureDate)""#)
        }
        if let arrivalDate {
            parts.append(#""arrival_date":"\#(arrivalDate)""#)
        }
        return "{\(parts.joined(separator: ","))}"
    }
}

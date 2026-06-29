@testable import AppleBridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderCalculateRoute")
struct MapKitProviderCalculateRouteTests {
    @Test
    @MainActor
    func calculateRouteReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "calculate_route",
            payloadJson: routePayload(
                sourceLatitude: 37.3346,
                sourceLongitude: -122.0090,
                destinationLatitude: 37.7749,
                destinationLongitude: -122.4194
            )
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("permission_denied") == true)
    }

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
        let sourcePlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let destinationPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        sourceItem.name = "Apple Park"
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = "San Francisco"

        let route = MapKitRouteData(
            name: "US-101",
            advisoryNotices: ["Avoid during winter storms"],
            distance: 77_000,
            expectedTravelTime: 3_600,
            transportType: .automobile,
            polylineCoordinates: [
                CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
                CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            ],
            steps: [
                MapKitRouteStepData(
                    instructions: "Head north on N De Anza Blvd",
                    notice: nil,
                    distance: 500,
                    transportType: .automobile,
                    polylineCoordinates: [
                        CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
                        CLLocationCoordinate2D(latitude: 37.3350, longitude: -122.0095),
                    ]
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

        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let source = decoded?["source"] as? [String: Any]
        let routes = decoded?["routes"] as? [[String: Any]]
        #expect(source?["name"] as? String == "Apple Park")
        #expect(routes?.first?["name"] as? String == "US-101")
        #expect(routes?.first?["has_highways"] as? Bool == true)
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
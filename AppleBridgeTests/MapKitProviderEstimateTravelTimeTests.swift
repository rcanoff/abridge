@testable import AppleBridge
import CoreLocation
import MapKit
import Testing

@Suite("MapKitProviderEstimateTravelTime")
struct MapKitProviderEstimateTravelTimeTests {
    @Test
    @MainActor
    func estimateTravelTimeReturnsPermissionDeniedWhenUnauthorized() {
        let store = MockMapKitStore()
        store.authorizationStatus = .denied
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "estimate_travel_time",
            payloadJson: etaPayload(
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
    func estimateTravelTimeRequiresSourceAndDestination() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(operation: "estimate_travel_time", payloadJson: "{}")
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
    }

    @Test
    @MainActor
    func estimateTravelTimeRejectsBothDepartureAndArrivalDates() {
        let provider = MapKitProvider(store: MockMapKitStore())
        let response = provider.handle(
            operation: "estimate_travel_time",
            payloadJson: etaPayload(
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
    func estimateTravelTimeReturnsSerializedResponse() throws {
        let store = makeSerializedETAStore()
        let provider = MapKitProvider(store: store)
        let response = provider.handle(
            operation: "estimate_travel_time",
            payloadJson: etaPayload(
                sourceLatitude: 37.3346,
                sourceLongitude: -122.0090,
                destinationLatitude: 37.7749,
                destinationLongitude: -122.4194,
                transportType: "walking"
            )
        )

        try expectSerializedEstimateTravelTimeResponse(response, store: store)
    }

    @MainActor
    private func makeSerializedETAStore() -> MockMapKitStore {
        let sourcePlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let destinationPlacemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: 37.7749,
            longitude: -122.4194
        ))
        let sourceItem = MKMapItem(placemark: sourcePlacemark)
        sourceItem.name = "Apple Park"
        let destinationItem = MKMapItem(placemark: destinationPlacemark)
        destinationItem.name = "San Francisco"

        let departureDate = Date(timeIntervalSince1970: 1_718_000_000)
        let arrivalDate = departureDate.addingTimeInterval(3600)

        let store = MockMapKitStore()
        store.estimateTravelTimeResults = [
            MapKitEstimateTravelTimeResult(
                source: sourceItem,
                destination: destinationItem,
                expectedTravelTime: 3600,
                distance: 77000,
                expectedArrivalDate: arrivalDate,
                expectedDepartureDate: departureDate,
                transportType: .automobile
            ),
        ]
        return store
    }

    @MainActor
    private func expectSerializedEstimateTravelTimeResponse(
        _ response: ProviderResponse,
        store: MockMapKitStore
    ) throws {
        #expect(response.ok == true)
        let data = try #require(response.payloadJson.data(using: .utf8))
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let source = decoded?["source"] as? [String: Any]
        #expect(source?["name"] as? String == "Apple Park")
        #expect(decoded?["expected_travel_time"] as? Double == 3600)
        #expect(decoded?["distance"] as? Double == 77000)
        #expect(decoded?["expected_arrival_date"] as? String == "2024-06-10T07:13:20Z")
        #expect(decoded?["expected_departure_date"] as? String == "2024-06-10T06:13:20Z")
        let transportType = decoded?["transport_type"] as? [String]
        #expect(transportType == ["automobile"])
        #expect(store.lastEstimateTravelTimeRequest?.transportType == .walking)
    }

    private func etaPayload(
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

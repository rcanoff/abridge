@testable import AppleBridge
import CoreLocation
import Foundation
import MapKit
import Testing

@Suite("MapKitSerialization")
struct MapKitSerializationTests {
    @Test
    func mapItemJSONObjectIncludesTopLevelKeys() {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090))
        let item = MKMapItem(placemark: placemark)
        item.name = "Test Place"
        item.phoneNumber = "+1 555 0100"

        let json = MapKitSerialization.mapItemJSONObject(from: item)
        #expect(json["name"] as? String == "Test Place")
        #expect(json["phone_number"] as? String == item.phoneNumber)
        #expect(json.keys.contains("placemark"))
        #expect(json.keys.contains("is_current_location"))
        #expect(json.keys.contains("location"))
        #expect(json.keys.contains("address"))
        #expect(json.keys.contains("address_representations"))
        #expect(json.keys.contains("point_of_interest_category"))
        #expect(json.keys.contains("time_zone"))
        #expect(json.keys.contains("url"))
        #expect(json.keys.contains("identifier"))
    }

    @Test
    func locationJSONObjectPreservesNegativeCourseAndSpeed() {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: -1,
            speed: -1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let json = MapKitSerialization.locationJSONObject(from: location) as? [String: Any]
        #expect(json?["course"] as? Double == -1)
        #expect(json?["speed"] as? Double == -1)
        #expect((json?["course"] is NSNull) == false)
        #expect((json?["speed"] is NSNull) == false)
    }

    @Test
    func placemarkJSONObjectPreservesNegativeAltitudeValues() {
        let location = NegativeAltitudeTestLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            altitude: -50,
            ellipsoidalAltitude: -30
        )
        let placemark = PlacemarkWithLocationTestDouble(location: location)

        let json = MapKitSerialization.placemarkJSONObject(from: placemark)
        #expect(json["altitude"] as? Double == -50)
        #expect(json["ellipsoidal_altitude"] as? Double == -30)
        #expect((json["altitude"] is NSNull) == false)
        #expect((json["ellipsoidal_altitude"] is NSNull) == false)
    }

    @Test
    func coordinateRegionJSONObjectPreservesSpan() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 2),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)
        )
        let json = MapKitSerialization.coordinateRegionJSONObject(from: region)
        let center = json["center"] as? [String: Any]
        #expect(center?["latitude"] as? Double == 1)
        #expect(center?["longitude"] as? Double == 2)
        let span = json["span"] as? [String: Any]
        #expect(span?["latitude_delta"] as? Double == 0.1)
        #expect(span?["longitude_delta"] as? Double == 0.2)
    }
}

private final class NegativeAltitudeTestLocation: CLLocation, @unchecked Sendable {
    private let testEllipsoidalAltitude: Double

    init(
        coordinate: CLLocationCoordinate2D,
        altitude: Double,
        ellipsoidalAltitude: Double
    ) {
        testEllipsoidalAltitude = ellipsoidalAltitude
        super.init(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var ellipsoidalAltitude: CLLocationDistance {
        testEllipsoidalAltitude
    }
}

private final class PlacemarkWithLocationTestDouble: MKPlacemark, @unchecked Sendable {
    private let testLocation: CLLocation

    init(location: CLLocation) {
        testLocation = location
        super.init(coordinate: location.coordinate)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var location: CLLocation? {
        testLocation
    }
}

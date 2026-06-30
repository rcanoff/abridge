@testable import AppleBridge
import CoreLocation
import Foundation
import MapKit
import Testing

@Suite("MapKitSerialization")
struct MapKitSerializationTests {
    @Test
    func mapItemJSONObjectIncludesTopLevelKeys() {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let item = MKMapItem(location: location, address: nil)
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
    func mapItemPlacemarkJSONObjectPreservesNegativeAltitudeValues() {
        let location = NegativeAltitudeTestLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            altitude: -50,
            ellipsoidalAltitude: -30
        )
        let item = SparseMapItemTestDouble(location: location)

        let json = MapKitSerialization.mapItemPlacemarkJSONObject(from: item)
        #expect(json["altitude"] as? Double == -50)
        #expect(json["ellipsoidal_altitude"] as? Double == -30)
        #expect((json["altitude"] is NSNull) == false)
        #expect((json["ellipsoidal_altitude"] is NSNull) == false)
    }

    @Test
    func mapItemPlacemarkJSONObjectBuildsFromLocationWhenPlacemarkSparse() {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090),
            altitude: 12.3,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 3.0,
            timestamp: Date(timeIntervalSince1970: 1_751_280_000)
        )
        let item = MKMapItem(location: location, address: nil)

        let json = MapKitSerialization.mapItemPlacemarkJSONObject(from: item)
        let coordinate = json["coordinate"] as? [String: Any]
        #expect(coordinate?["latitude"] as? Double == 37.3346)
        #expect(coordinate?["longitude"] as? Double == -122.0090)
        #expect(json.keys.contains("altitude"))
        #expect(json.keys.contains("ellipsoidal_altitude"))
        #expect(json.keys.contains("address_dictionary"))
        #expect(json.keys.contains("country_code"))
        #expect(json.keys.contains("postal_address"))
    }

    @Test
    func mapItemPlacemarkJSONObjectSerializesPlacemarkRegionViaKVC() {
        let coordinate = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
        let item = MapKitTestFixtures.mapItem(coordinate: coordinate)

        let json = MapKitSerialization.mapItemPlacemarkJSONObject(from: item)
        let region = json["region"] as? [String: Any]
        #expect(region != nil)
        #expect((json["region"] is NSNull) == false)
        let center = region?["center"] as? [String: Any]
        #expect(center?["latitude"] as? Double == 37.3346)
        #expect(center?["longitude"] as? Double == -122.0090)
        #expect((region?["radius"] as? Double ?? -1) >= 0)
    }

    @Test
    func mapItemPlacemarkJSONObjectPreservesPlacemarkMetadataViaKVC() {
        let coordinate = CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0090)
        let item = MapKitTestFixtures.mapItem(coordinate: coordinate)

        let json = MapKitSerialization.mapItemPlacemarkJSONObject(from: item)
        let coordinateJSON = json["coordinate"] as? [String: Any]
        #expect(coordinateJSON?["latitude"] as? Double == 37.3346)
        #expect(coordinateJSON?["longitude"] as? Double == -122.0090)
        #expect(json.keys.contains("country_code"))
        #expect(json.keys.contains("postal_address"))
        #expect(json.keys.contains("address_dictionary"))
        #expect(json.keys.contains("inland_water"))
        #expect(json.keys.contains("ocean"))
        #expect(json.keys.contains("areas_of_interest"))
    }

    @Test
    func mapItemPlacemarkJSONObjectUsesNullCoordinateWhenLocationUnavailable() {
        let coordinate = CLLocationCoordinate2D(latitude: 12.5, longitude: -45.6)
        let placemark = MapKitTestFixtures.placemarkObject(for: coordinate)
        let item = SparseMapItemTestDouble(location: nil, placemark: placemark)

        let json = MapKitSerialization.mapItemPlacemarkJSONObject(from: item)
        let serializedCoordinate = json["coordinate"] as? [String: Any]
        #expect(serializedCoordinate?["latitude"] as? Double == 12.5)
        #expect(serializedCoordinate?["longitude"] as? Double == -45.6)
        #expect(json.keys.contains("altitude"))
        #expect(json.keys.contains("ellipsoidal_altitude"))
    }

    @Test
    func mapItemPlacemarkJSONObjectUsesNullRegionWhenPlacemarkUnavailable() {
        let item = SparseMapItemTestDouble(location: nil, placemark: nil)

        let json = MapKitSerialization.mapItemPlacemarkJSONObject(from: item)
        #expect((json["coordinate"] is NSNull) == true)
        #expect((json["region"] is NSNull) == true)
        #expect(json.keys.contains("altitude"))
        #expect(json.keys.contains("ellipsoidal_altitude"))
    }

    @Test
    func mapItemJSONObjectSerializesSparseItemWithNilLocationWithoutCrashing() {
        let coordinate = CLLocationCoordinate2D(latitude: 12.5, longitude: -45.6)
        let placemark = MapKitTestFixtures.placemarkObject(for: coordinate)
        let item = SparseMapItemTestDouble(location: nil, placemark: placemark)
        item.name = "Sparse Place"

        let json = MapKitSerialization.mapItemJSONObject(from: item)
        #expect(json["name"] as? String == "Sparse Place")
        #expect((json["location"] is NSNull) == true)
        let placemarkJSON = json["placemark"] as? [String: Any]
        let serializedCoordinate = placemarkJSON?["coordinate"] as? [String: Any]
        #expect(serializedCoordinate?["latitude"] as? Double == 12.5)
        #expect(serializedCoordinate?["longitude"] as? Double == -45.6)
        #expect(placemarkJSON?.keys.contains("altitude") == true)
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

private final class SparseMapItemTestDouble: MKMapItem, @unchecked Sendable {
    private let testLocation: CLLocation?
    private let testPlacemark: AnyObject?

    init(location: CLLocation?, placemark: AnyObject? = nil) {
        testLocation = location
        testPlacemark = placemark
        super.init()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func value(forKey key: String) -> Any? {
        if key == "location" {
            return testLocation
        }
        if key == "placemark" {
            return testPlacemark
        }
        return super.value(forKey: key)
    }
}

import CoreLocation
import MapKit

enum MapKitTestFixtures {
    static func mapItem(coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
    }

    /// Placemark object from a modern `MKMapItem` for KVC injection in sparse test doubles.
    static func placemarkObject(for coordinate: CLLocationCoordinate2D) -> AnyObject? {
        mapItem(coordinate: coordinate).value(forKey: "placemark") as AnyObject?
    }
}

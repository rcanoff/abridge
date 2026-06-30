import Contacts
import CoreLocation
import Foundation
import MapKit

extension MapKitSerialization {
    static func mapItemPlacemarkJSONObject(from item: MKMapItem) -> [String: Any] {
        let location = optionalLocation(from: item)

        return [
            "coordinate": location.map { coordinateJSONObject(from: $0.coordinate) } ?? NSNull(),
            "altitude": location?.altitude ?? NSNull(),
            "ellipsoidal_altitude": location?.ellipsoidalAltitude ?? NSNull(),
            "region": regionJSONObject(from: location),
            "time_zone": jsonValueTimeZone(item.timeZone),
            "country_code": NSNull(),
            "inland_water": NSNull(),
            "ocean": NSNull(),
            "areas_of_interest": NSNull(),
            "postal_address": NSNull(),
            "address_dictionary": NSNull(),
        ]
    }

    static func addressJSONObject(from address: MKAddress?) -> Any {
        guard let address else { return NSNull() }

        return [
            "full_address": address.fullAddress,
            "short_address": jsonValue(address.shortAddress),
            "region": NSNull(),
            "sub_region": NSNull(),
            "city": NSNull(),
            "sub_city": NSNull(),
            "street": NSNull(),
            "sub_street": NSNull(),
            "postal_code": NSNull(),
            "country": NSNull(),
            "country_code": NSNull(),
            "formatted_address_lines": NSNull(),
            "representations": NSNull(),
        ]
    }

    static func addressRepresentationsJSONObject(from representations: MKAddressRepresentations) -> [String: Any] {
        [
            "full_address": jsonValue(
                representations.fullAddress(includingRegion: true, singleLine: false)
            ),
            "short_address": jsonValue(
                representations.fullAddress(includingRegion: false, singleLine: true)
            ),
            "city_name": jsonValue(representations.cityName),
            "city_with_context": jsonValue(representations.cityWithContext),
            "region_name": jsonValue(representations.regionName),
            "region_code": NSNull(),
            "formatted_address_lines": NSNull(),
        ]
    }

    static func postalAddressJSONObject(from address: CNPostalAddress?) -> Any {
        guard let address else { return NSNull() }

        return [
            "street": address.street,
            "sub_locality": address.subLocality,
            "city": address.city,
            "sub_administrative_area": address.subAdministrativeArea,
            "state": address.state,
            "postal_code": address.postalCode,
            "country": address.country,
            "iso_country_code": address.isoCountryCode,
        ]
    }

    static func addressRepresentationsJSONArray(from representations: MKAddressRepresentations?) -> Any {
        guard let representations else { return NSNull() }
        return [addressRepresentationsJSONObject(from: representations)]
    }

    /// Sparse MapKit items can surface a nil ObjC `location` at runtime despite the non-optional Swift type.
    static func optionalLocation(from item: MKMapItem) -> CLLocation? {
        (item as AnyObject).value(forKey: "location") as? CLLocation
    }

    private static func regionJSONObject(from location: CLLocation?) -> Any {
        guard let location else { return NSNull() }

        let region = CLCircularRegion(
            center: location.coordinate,
            radius: 0,
            identifier: ""
        )
        return circularRegionJSONObject(from: region)
    }

    private static func circularRegionJSONObject(from region: CLCircularRegion) -> [String: Any] {
        [
            "center": coordinateJSONObject(from: region.center),
            "radius": region.radius,
            "identifier": region.identifier,
        ]
    }
}
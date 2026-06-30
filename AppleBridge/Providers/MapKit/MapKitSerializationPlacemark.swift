import Contacts
import CoreLocation
import Foundation
import MapKit

extension MapKitSerialization {
    static func mapItemPlacemarkJSONObject(from item: MKMapItem) -> [String: Any] {
        let placemarkObject = optionalPlacemarkObject(from: item)
        let itemLocation = optionalLocation(from: item)
        let placemarkLocation = optionalPlacemarkLocation(from: placemarkObject)

        var coordinate = coordinateFromPlacemarkObject(placemarkObject)
        var altitude: Any = placemarkLocation?.altitude ?? NSNull()
        var ellipsoidalAltitude: Any = placemarkEllipsoidalAltitude(from: placemarkLocation) ?? NSNull()

        if let itemLocation {
            coordinate = itemLocation.coordinate
            altitude = itemLocation.altitude
            ellipsoidalAltitude = itemLocation.ellipsoidalAltitude
        }

        let placemarkTimeZone = optionalPlacemarkTimeZone(from: placemarkObject)

        return [
            "coordinate": coordinate.map { coordinateJSONObject(from: $0) } ?? NSNull(),
            "altitude": altitude,
            "ellipsoidal_altitude": ellipsoidalAltitude,
            "region": regionJSONObject(from: optionalPlacemarkRegion(from: placemarkObject)),
            "time_zone": jsonValueTimeZone(placemarkTimeZone ?? item.timeZone),
            "country_code": jsonValue(optionalPlacemarkCountryCode(from: placemarkObject)),
            "inland_water": jsonValue(optionalPlacemarkString(from: placemarkObject, key: "inlandWater")),
            "ocean": jsonValue(optionalPlacemarkString(from: placemarkObject, key: "ocean")),
            "areas_of_interest": jsonValue(optionalPlacemarkStringArray(from: placemarkObject, key: "areasOfInterest")),
            "postal_address": postalAddressJSONObject(from: optionalPlacemarkPostalAddress(from: placemarkObject)),
            "address_dictionary": addressDictionaryJSONObject(
                from: optionalPlacemarkAddressDictionary(from: placemarkObject)
            ),
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

    private static func optionalPlacemarkObject(from item: MKMapItem) -> AnyObject? {
        kvcValue(on: item as AnyObject, key: "placemark") as? AnyObject
    }

    private static func optionalPlacemarkLocation(from placemarkObject: AnyObject?) -> CLLocation? {
        kvcValue(on: placemarkObject, key: "location") as? CLLocation
    }

    private static func coordinateFromPlacemarkObject(_ placemarkObject: AnyObject?) -> CLLocationCoordinate2D? {
        if let coordinate = optionalPlacemarkLocation(from: placemarkObject)?.coordinate {
            return coordinate
        }

        return coordinateFromKVCValue(kvcValue(on: placemarkObject, key: "coordinate"))
    }

    private static func kvcValue(on object: AnyObject?, key: String) -> Any? {
        guard let object else { return nil }
        return MapKitSafeValueForKey(object, key)
    }

    private static func coordinateFromKVCValue(_ value: Any?) -> CLLocationCoordinate2D? {
        guard let value else { return nil }

        if let coordinate = value as? CLLocationCoordinate2D {
            return coordinate
        }

        guard let nsValue = value as? NSValue else { return nil }
        guard String(cString: nsValue.objCType) == "{CLLocationCoordinate2D=dd}" else { return nil }

        var coordinate = CLLocationCoordinate2D()
        nsValue.getValue(&coordinate)
        return coordinate
    }

    private static func placemarkEllipsoidalAltitude(from location: CLLocation?) -> Double? {
        guard let location else { return nil }
        return kvcValue(on: location, key: "ellipsoidalAltitude") as? Double ?? location.ellipsoidalAltitude
    }

    private static func optionalPlacemarkRegion(from placemarkObject: AnyObject?) -> CLRegion? {
        kvcValue(on: placemarkObject, key: "region") as? CLRegion
    }

    private static func optionalPlacemarkTimeZone(from placemarkObject: AnyObject?) -> TimeZone? {
        kvcValue(on: placemarkObject, key: "timeZone") as? TimeZone
    }

    private static func optionalPlacemarkCountryCode(from placemarkObject: AnyObject?) -> String? {
        if let countryCode = kvcValue(on: placemarkObject, key: "countryCode") as? String {
            return countryCode
        }
        return kvcValue(on: placemarkObject, key: "isoCountryCode") as? String
    }

    private static func optionalPlacemarkString(from placemarkObject: AnyObject?, key: String) -> String? {
        kvcValue(on: placemarkObject, key: key) as? String
    }

    private static func optionalPlacemarkStringArray(from placemarkObject: AnyObject?, key: String) -> [String]? {
        kvcValue(on: placemarkObject, key: key) as? [String]
    }

    private static func optionalPlacemarkPostalAddress(from placemarkObject: AnyObject?) -> CNPostalAddress? {
        kvcValue(on: placemarkObject, key: "postalAddress") as? CNPostalAddress
    }

    private static func optionalPlacemarkAddressDictionary(from placemarkObject: AnyObject?) -> [AnyHashable: Any]? {
        kvcValue(on: placemarkObject, key: "addressDictionary") as? [AnyHashable: Any]
    }

    private static func regionJSONObject(from region: CLRegion?) -> Any {
        guard let region else { return NSNull() }

        if let circularRegion = region as? CLCircularRegion {
            return circularRegionJSONObject(from: circularRegion)
        }

        return [
            "center": coordinateFromKVCValue(kvcValue(on: region as AnyObject, key: "center"))
                .map { coordinateJSONObject(from: $0) } ?? NSNull(),
            "radius": jsonValue(kvcValue(on: region as AnyObject, key: "radius")),
            "identifier": jsonValue(kvcValue(on: region as AnyObject, key: "identifier") as? String),
        ]
    }

    private static func circularRegionJSONObject(from region: CLCircularRegion) -> [String: Any] {
        [
            "center": coordinateJSONObject(from: region.center),
            "radius": region.radius,
            "identifier": region.identifier,
        ]
    }

    private static func addressDictionaryJSONObject(from dictionary: [AnyHashable: Any]?) -> Any {
        guard let dictionary else { return NSNull() }

        var payload: [String: Any] = [:]
        for (key, value) in dictionary {
            guard let key = key as? String else { continue }
            payload[key] = jsonValue(value)
        }
        return payload
    }
}

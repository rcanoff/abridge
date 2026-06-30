import Contacts
import CoreLocation
import Foundation
import MapKit

extension MapKitSerialization {
    static func mapItemPlacemarkJSONObject(from item: MKMapItem) -> [String: Any] {
        let placemark = item.placemark
        if hasEnrichedPlacemarkData(placemark) {
            return placemarkJSONObject(from: placemark)
        }

        return placemarkJSONObjectFromMapItemFields(item)
    }

    static func placemarkJSONObject(from placemark: MKPlacemark) -> [String: Any] {
        [
            "coordinate": coordinateJSONObject(from: placemark.coordinate),
            "altitude": placemark.location?.altitude ?? NSNull(),
            "ellipsoidal_altitude": placemark.location?.ellipsoidalAltitude ?? NSNull(),
            "region": regionJSONObject(from: placemark.region),
            "time_zone": jsonValueTimeZone(placemark.timeZone),
            "country_code": jsonValue(placemark.countryCode ?? placemark.isoCountryCode),
            "inland_water": jsonValue(placemark.inlandWater),
            "ocean": jsonValue(placemark.ocean),
            "areas_of_interest": jsonValue(placemark.areasOfInterest),
            "postal_address": postalAddressJSONObject(from: placemark.postalAddress),
            "address_dictionary": addressDictionaryJSONObject(from: placemark.addressDictionary),
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

    private static func placemarkJSONObjectFromMapItemFields(_ item: MKMapItem) -> [String: Any] {
        var json = placemarkJSONObject(from: item.placemark)

        if let location = optionalLocation(from: item) {
            json["coordinate"] = coordinateJSONObject(from: location.coordinate)
            json["altitude"] = location.altitude
            json["ellipsoidal_altitude"] = location.ellipsoidalAltitude
        }

        json["time_zone"] = jsonValueTimeZone(item.timeZone)

        return json
    }

    /// Sparse MapKit items can surface a nil ObjC `location` at runtime despite the non-optional Swift type.
    static func optionalLocation(from item: MKMapItem) -> CLLocation? {
        (item as AnyObject).value(forKey: "location") as? CLLocation
    }

    private static func hasEnrichedPlacemarkData(_ placemark: MKPlacemark) -> Bool {
        placemark.countryCode != nil
            || placemark.isoCountryCode != nil
            || placemark.inlandWater != nil
            || placemark.ocean != nil
            || placemark.areasOfInterest != nil
            || placemark.addressDictionary != nil
            || placemark.timeZone != nil
            || hasMeaningfulPostalAddress(placemark.postalAddress)
    }

    private static func hasMeaningfulPostalAddress(_ address: CNPostalAddress?) -> Bool {
        guard let address else { return false }

        return !address.street.isEmpty
            || !address.subLocality.isEmpty
            || !address.city.isEmpty
            || !address.subAdministrativeArea.isEmpty
            || !address.state.isEmpty
            || !address.postalCode.isEmpty
            || !address.country.isEmpty
            || !address.isoCountryCode.isEmpty
    }

    private static func regionJSONObject(from region: CLRegion?) -> Any {
        guard let region else { return NSNull() }

        if let circularRegion = region as? CLCircularRegion {
            return circularRegionJSONObject(from: circularRegion)
        }

        return [
            "center": coordinateJSONObject(from: region.center),
            "radius": region.radius,
            "identifier": region.identifier,
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

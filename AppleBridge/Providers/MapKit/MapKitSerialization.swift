import Contacts
import CoreLocation
import Foundation
import MapKit

enum MapKitSerialization {
    static func jsonString(from object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw MapKitProviderError.serializationFailed
        }
        return string
    }

    static func mapItemJSONObject(from item: MKMapItem) -> [String: Any] {
        [
            "name": jsonValue(item.name),
            "phone_number": jsonValue(item.phoneNumber),
            "url": jsonValueURL(item.url),
            "time_zone": jsonValueTimeZone(item.timeZone),
            "point_of_interest_category": jsonValuePOICategory(item.pointOfInterestCategory),
            "is_current_location": item.isCurrentLocation,
            "identifier": jsonValueMapItemIdentifier(item.identifier),
            "location": locationJSONObject(from: item.location),
            "placemark": placemarkJSONObject(from: item.placemark),
            "address": addressJSONObject(from: item.address),
            "address_representations": addressRepresentationsJSONArray(from: item.addressRepresentations),
        ]
    }

    static func coordinateRegionJSONObject(from region: MKCoordinateRegion) -> [String: Any] {
        [
            "center": coordinateJSONObject(from: region.center),
            "span": [
                "latitude_delta": region.span.latitudeDelta,
                "longitude_delta": region.span.longitudeDelta,
            ],
        ]
    }

    static func searchResponseJSONObject(
        mapItems: [MKMapItem],
        boundingRegion: MKCoordinateRegion?
    ) -> [String: Any] {
        [
            "map_items": mapItems.map(mapItemJSONObject(from:)),
            "bounding_region": boundingRegion.map(coordinateRegionJSONObject(from:)) ?? NSNull(),
        ]
    }

    static func reverseGeocodeResponseJSONObject(mapItems: [MKMapItem]) -> [String: Any] {
        [
            "map_items": mapItems.map(mapItemJSONObject(from:)),
        ]
    }

    static func calculateRouteResponseJSONObject(result: MapKitCalculateRouteResult) -> [String: Any] {
        [
            "source": mapItemJSONObject(from: result.source),
            "destination": mapItemJSONObject(from: result.destination),
            "routes": result.routes.map(routeJSONObject(from:)),
        ]
    }

    static func routeJSONObject(from route: MapKitRouteData) -> [String: Any] {
        [
            "name": route.name,
            "advisory_notices": route.advisoryNotices,
            "distance": route.distance,
            "expected_travel_time": route.expectedTravelTime,
            "transport_type": transportTypeJSONArray(from: route.transportType),
            "polyline": polylineJSONObject(
                coordinates: route.polylineCoordinates,
                title: route.polylineTitle,
                subtitle: route.polylineSubtitle
            ),
            "steps": route.steps.map(routeStepJSONObject(from:)),
            "has_tolls": route.hasTolls,
            "has_highways": route.hasHighways,
        ]
    }

    static func routeStepJSONObject(from step: MapKitRouteStepData) -> [String: Any] {
        [
            "instructions": step.instructions,
            "notice": jsonValue(step.notice),
            "distance": step.distance,
            "transport_type": transportTypeJSONArray(from: step.transportType),
            "polyline": polylineJSONObject(
                coordinates: step.polylineCoordinates,
                title: step.polylineTitle,
                subtitle: step.polylineSubtitle
            ),
        ]
    }

    static func polylineJSONObject(
        coordinates: [CLLocationCoordinate2D],
        title: String?,
        subtitle: String?
    ) -> [String: Any] {
        [
            "title": jsonValue(title),
            "subtitle": jsonValue(subtitle),
            "point_count": coordinates.count,
            "coordinates": coordinates.map(coordinateJSONObject(from:)),
        ]
    }

    // MARK: - Nested types

    static func locationJSONObject(from location: CLLocation?) -> Any {
        guard let location else { return NSNull() }

        return [
            "coordinate": coordinateJSONObject(from: location.coordinate),
            "altitude": location.altitude,
            "horizontal_accuracy": location.horizontalAccuracy,
            "vertical_accuracy": location.verticalAccuracy,
            "course": location.course,
            "speed": location.speed,
            "timestamp": iso8601String(from: location.timestamp),
            "floor": jsonValueFloor(location.floor),
        ]
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

    // MARK: - Helpers

    private static func coordinateJSONObject(from coordinate: CLLocationCoordinate2D) -> [String: Any] {
        [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
        ]
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

    private static func addressRepresentationsJSONArray(from representations: MKAddressRepresentations?) -> Any {
        guard let representations else { return NSNull() }
        return [addressRepresentationsJSONObject(from: representations)]
    }

    private static func jsonValue(_ string: String?) -> Any {
        string ?? NSNull()
    }

    private static func jsonValue(_ number: Double?) -> Any {
        guard let number, number >= 0 else { return NSNull() }
        return number
    }

    private static func jsonValue(_ values: [String]?) -> Any {
        values ?? NSNull()
    }

    private static func jsonValue(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    private static func jsonValueURL(_ url: URL?) -> Any {
        url?.absoluteString ?? NSNull()
    }

    private static func jsonValueTimeZone(_ timeZone: TimeZone?) -> Any {
        timeZone?.identifier ?? NSNull()
    }

    private static func jsonValuePOICategory(_ category: MKPointOfInterestCategory?) -> Any {
        category?.rawValue ?? NSNull()
    }

    private static func jsonValueMapItemIdentifier(_ identifier: MKMapItem.Identifier?) -> Any {
        identifier?.rawValue ?? NSNull()
    }

    private static func jsonValueFloor(_ floor: CLFloor?) -> Any {
        guard let floor else { return NSNull() }
        return [
            "level": floor.level,
        ]
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func transportTypeJSONArray(from transportType: MKDirectionsTransportType) -> [String] {
        if transportType == .any {
            return ["any"]
        }

        var values: [String] = []
        if transportType.contains(.automobile) {
            values.append("automobile")
        }
        if transportType.contains(.walking) {
            values.append("walking")
        }
        if transportType.contains(.transit) {
            values.append("transit")
        }
        if transportType.contains(.cycling) {
            values.append("cycling")
        }
        return values.isEmpty ? ["any"] : values
    }
}

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
            "location": locationJSONObject(from: optionalLocation(from: item)),
            "placemark": mapItemPlacemarkJSONObject(from: item),
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

    static func getCurrentLocationResponseJSONObject(location: CLLocation) -> [String: Any] {
        ["location": locationJSONObject(from: location)]
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

    static func estimateTravelTimeResponseJSONObject(result: MapKitEstimateTravelTimeResult) -> [String: Any] {
        [
            "source": mapItemJSONObject(from: result.source),
            "destination": mapItemJSONObject(from: result.destination),
            "expected_travel_time": result.expectedTravelTime,
            "distance": result.distance,
            "expected_arrival_date": iso8601String(from: result.expectedArrivalDate),
            "expected_departure_date": iso8601String(from: result.expectedDepartureDate),
            "transport_type": transportTypeJSONArray(from: result.transportType),
        ]
    }

    static func openNavigationResponseJSONObject(result: MapKitOpenNavigationResult) -> [String: Any] {
        var launchOptions: Any = NSNull()
        if let directionsMode = result.directionsMode {
            launchOptions = ["directions_mode": directionsMode]
        }

        return [
            "opened": result.opened,
            "source": mapItemJSONObject(from: result.source),
            "destination": mapItemJSONObject(from: result.destination),
            "transport_type": transportTypeJSONArray(from: result.transportType),
            "launch_options": launchOptions,
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

    // MARK: - Helpers

    static func coordinateJSONObject(from coordinate: CLLocationCoordinate2D) -> [String: Any] {
        [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
        ]
    }

    static func jsonValue(_ string: String?) -> Any {
        string ?? NSNull()
    }

    static func jsonValue(_ number: Double?) -> Any {
        guard let number, number >= 0 else { return NSNull() }
        return number
    }

    static func jsonValue(_ values: [String]?) -> Any {
        values ?? NSNull()
    }

    static func jsonValue(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    static func jsonValueURL(_ url: URL?) -> Any {
        url?.absoluteString ?? NSNull()
    }

    static func jsonValueTimeZone(_ timeZone: TimeZone?) -> Any {
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

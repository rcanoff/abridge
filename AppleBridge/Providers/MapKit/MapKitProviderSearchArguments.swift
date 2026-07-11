import CoreLocation
import Foundation
import MapKit

private enum MapKitPOICategoryCatalog {
    private static let knownCategories: [MKPointOfInterestCategory] = [
        .animalService,
        .airport,
        .amusementPark,
        .aquarium,
        .atm,
        .automotiveRepair,
        .bakery,
        .bank,
        .baseball,
        .basketball,
        .beach,
        .beauty,
        .bowling,
        .brewery,
        .cafe,
        .campground,
        .carRental,
        .castle,
        .conventionCenter,
        .distillery,
        .evCharger,
        .fairground,
        .fireStation,
        .fishing,
        .fitnessCenter,
        .foodMarket,
        .fortress,
        .gasStation,
        .golf,
        .goKart,
        .hiking,
        .hospital,
        .hotel,
        .kayaking,
        .landmark,
        .laundry,
        .library,
        .mailbox,
        .marina,
        .miniGolf,
        .movieTheater,
        .museum,
        .musicVenue,
        .nationalMonument,
        .nationalPark,
        .nightlife,
        .park,
        .parking,
        .pharmacy,
        .planetarium,
        .police,
        .postOffice,
        .publicTransport,
        .restaurant,
        .restroom,
        .rockClimbing,
        .rvPark,
        .school,
        .skatePark,
        .skating,
        .skiing,
        .soccer,
        .spa,
        .stadium,
        .store,
        .surfing,
        .swimming,
        .tennis,
        .theater,
        .university,
        .winery,
        .volleyball,
        .zoo,
    ]

    static let recognizedRawValues = Set(knownCategories.map(\.rawValue))
}

extension MapKitProvider {
    func requiredGeographicAnchor(in dictionary: [String: Any]) throws -> MKCoordinateRegion {
        let hasRegion = dictionary.keys.contains("region") && !(dictionary["region"] is NSNull)
        let hasCoordinate = dictionary.keys.contains("coordinate") && !(dictionary["coordinate"] is NSNull)

        guard hasRegion || hasCoordinate else {
            // Schema oneOf; offline path uses zero region (MapKit may fail at runtime).
            return MKCoordinateRegion()
        }
        guard !(hasRegion && hasCoordinate) else {
            throw MapKitProviderError.invalidArguments("provide region or coordinate, not both")
        }

        if hasRegion {
            return try requiredRegionArgument(in: dictionary)
        }

        let coordinate = try requiredCoordinateArgument(in: dictionary)
        let radiusMeters = try optionalRadiusMetersArgument(in: dictionary)
        return coordinateRegion(from: coordinate, radiusMeters: radiusMeters)
    }

    func optionalRegionArgument(in dictionary: [String: Any]) throws -> MKCoordinateRegion? {
        guard dictionary.keys.contains("region") else {
            return nil
        }

        if dictionary["region"] is NSNull {
            return nil
        }

        return try parseRegionDictionary(dictionary["region"])
    }

    func requiredRegionArgument(in dictionary: [String: Any]) throws -> MKCoordinateRegion {
        try parseRegionDictionary(dictionary["region"])
    }

    func requiredCoordinateArgument(in dictionary: [String: Any]) throws -> CLLocationCoordinate2D {
        guard dictionary.keys.contains("coordinate"), !(dictionary["coordinate"] is NSNull) else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }

        guard let coordinateDictionary = dictionary["coordinate"] as? [String: Any] else {
            throw MapKitProviderError.invalidArguments("coordinate must be an object")
        }

        let latitude = try requiredCoordinateComponent(
            named: "latitude",
            in: coordinateDictionary,
            minimum: -90,
            maximum: 90,
            prefix: "coordinate"
        )
        let longitude = try requiredCoordinateComponent(
            named: "longitude",
            in: coordinateDictionary,
            minimum: -180,
            maximum: 180,
            prefix: "coordinate"
        )

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func coordinateRegion(
        from coordinate: CLLocationCoordinate2D,
        radiusMeters: Double = 1000
    ) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        )
    }

    func optionalPOICategoryFilter(in dictionary: [String: Any]) throws -> MKPointOfInterestFilter? {
        let includingCategories = try optionalPOICategoryList(
            named: "including_categories",
            in: dictionary
        )
        let excludingCategories = try optionalPOICategoryList(
            named: "excluding_categories",
            in: dictionary
        )

        if includingCategories != nil, excludingCategories != nil {
            throw MapKitProviderError.invalidArguments(
                "provide including_categories or excluding_categories, not both"
            )
        }

        if let includingCategories {
            return MKPointOfInterestFilter(including: includingCategories)
        }
        if let excludingCategories {
            return MKPointOfInterestFilter(excluding: excludingCategories)
        }
        return nil
    }

    private func optionalRadiusMetersArgument(in dictionary: [String: Any]) throws -> Double {
        guard dictionary.keys.contains("radius_meters") else {
            return 1000
        }

        if dictionary["radius_meters"] is NSNull {
            return 1000
        }

        guard let value = dictionary["radius_meters"] as? Double else {
            throw MapKitProviderError.invalidArguments("radius_meters must be a number")
        }
        guard value > 0 else {
            throw MapKitProviderError.invalidArguments("radius_meters must be greater than 0")
        }

        return value
    }

    private func optionalPOICategoryList(
        named key: String,
        in dictionary: [String: Any]
    ) throws -> [MKPointOfInterestCategory]? {
        guard dictionary.keys.contains(key) else {
            return nil
        }

        if dictionary[key] is NSNull {
            return nil
        }

        guard let values = dictionary[key] as? [Any] else {
            throw MapKitProviderError.invalidArguments("\(key) must be an array or null")
        }

        guard !values.isEmpty else {
            return nil // schema minItems; offline empty means no filter
        }

        var categories: [MKPointOfInterestCategory] = []
        for value in values {
            guard let rawValue = value as? String else {
                throw MapKitProviderError.invalidArguments("\(key) items must be strings")
            }

            guard MapKitPOICategoryCatalog.recognizedRawValues.contains(rawValue) else {
                throw MapKitProviderError.invalidArguments("\(key) value \(rawValue) is not recognized")
            }

            categories.append(MKPointOfInterestCategory(rawValue: rawValue))
        }

        return categories
    }

    private func parseRegionDictionary(_ value: Any?) throws -> MKCoordinateRegion {
        guard let regionDictionary = value as? [String: Any] else {
            throw MapKitProviderError.invalidArguments("region must be an object or null")
        }

        guard let centerDictionary = regionDictionary["center"] as? [String: Any],
              let spanDictionary = regionDictionary["span"] as? [String: Any]
        else {
            throw MapKitProviderError.invalidArguments("region must be a complete object")
        }

        let latitude = try requiredCoordinateComponent(
            named: "latitude",
            in: centerDictionary,
            minimum: -90,
            maximum: 90,
            prefix: "region.center"
        )
        let longitude = try requiredCoordinateComponent(
            named: "longitude",
            in: centerDictionary,
            minimum: -180,
            maximum: 180,
            prefix: "region.center"
        )
        let latitudeDelta = try requiredPositiveSpanComponent(
            named: "latitude_delta",
            in: spanDictionary
        )
        let longitudeDelta = try requiredPositiveSpanComponent(
            named: "longitude_delta",
            in: spanDictionary
        )

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    func requiredCoordinateComponent(
        named key: String,
        in dictionary: [String: Any],
        minimum: Double,
        maximum: Double,
        prefix: String = "region.center"
    ) throws -> Double {
        guard let value = dictionary[key] as? Double else {
            throw MapKitProviderError.invalidArguments("\(prefix).\(key) must be a number")
        }
        guard value >= minimum, value <= maximum else {
            throw MapKitProviderError.invalidArguments(
                "\(prefix).\(key) must be between \(minimum) and \(maximum)"
            )
        }
        return value
    }

    func requiredPositiveSpanComponent(
        named key: String,
        in dictionary: [String: Any]
    ) throws -> Double {
        guard let value = dictionary[key] as? Double else {
            throw MapKitProviderError.invalidArguments("region.span.\(key) must be a number")
        }
        guard value > 0 else {
            throw MapKitProviderError.invalidArguments("region.span.\(key) must be greater than 0")
        }
        return value
    }
}

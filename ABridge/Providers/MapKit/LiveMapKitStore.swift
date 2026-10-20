import AppKit
import CoreLocation
import Foundation
@preconcurrency import MapKit

typealias MapKitSearchFetch = MainQueueCallbackWait<MapKitProviderError>

/// Builds the MapKit request used for query-less nearby POI search.
///
/// `MKLocalSearch.Request` with only `resultTypes = .pointOfInterest` and no
/// `naturalLanguageQuery` always fails with MKErrorDomain code 4 (placemark not found).
enum MapKitNearbySearchSupport {
    static func pointsOfInterestRequest(
        region: MKCoordinateRegion,
        filter: MKPointOfInterestFilter?
    ) -> MKLocalPointsOfInterestRequest {
        let request = MKLocalPointsOfInterestRequest(coordinateRegion: region)
        request.pointOfInterestFilter = filter ?? .includingAll
        return request
    }
}

struct LiveMapKitStore: MapKitStoreing, @unchecked Sendable {
    func searchPlaces(request: MapKitSearchRequest) throws -> MapKitSearchResult {
        let mkRequest = MKLocalSearch.Request()
        mkRequest.naturalLanguageQuery = request.query
        if let region = request.region {
            mkRequest.region = region
        }
        mkRequest.regionPriority = request.regionPriority
        if let resultTypes = request.resultTypes {
            mkRequest.resultTypes = resultTypes
        }

        let search = MKLocalSearch(request: mkRequest)
        let result = MapKitSearchFetch.AsyncBridgeResult<MKLocalSearch.Response>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit search") { complete in
            search.start { response, error in
                if let error {
                    result.setError(error)
                } else if let response {
                    result.setValue(response)
                } else {
                    result.setError(MapKitProviderError.mapkitError("MapKit search returned no response"))
                }
                complete()
            }
        }

        let response = try result.get()
        return MapKitSearchResult(mapItems: response.mapItems, boundingRegion: response.boundingRegion)
    }

    func searchNearby(request: MapKitSearchNearbyRequest) throws -> MapKitSearchResult {
        let poiRequest = MapKitNearbySearchSupport.pointsOfInterestRequest(
            region: request.region,
            filter: request.pointOfInterestFilter
        )
        let search = MKLocalSearch(request: poiRequest)
        let result = MapKitSearchFetch.AsyncBridgeResult<MKLocalSearch.Response>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit nearby search") { complete in
            search.start { response, error in
                if let error {
                    result.setError(error)
                } else if let response {
                    result.setValue(response)
                } else {
                    result.setError(MapKitProviderError.mapkitError("MapKit search returned no response"))
                }
                complete()
            }
        }

        let response = try result.get()
        return MapKitSearchResult(mapItems: response.mapItems, boundingRegion: response.boundingRegion)
    }

    func reverseGeocode(request: MapKitReverseGeocodeRequest) throws -> [MKMapItem] {
        let location = CLLocation(
            latitude: request.coordinate.latitude,
            longitude: request.coordinate.longitude
        )
        guard let mkRequest = MKReverseGeocodingRequest(location: location) else {
            throw MapKitProviderError.mapkitError("MapKit reverse geocode request could not be created")
        }
        let result = MapKitSearchFetch.AsyncBridgeResult<[MKMapItem]>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit reverse geocode") { complete in
            // Detached so a main-thread waiter is not blocked behind MainActor Task scheduling.
            Task.detached {
                defer { complete() }
                do {
                    let mapItems = try await mkRequest.mapItems
                    result.setValue(mapItems)
                } catch {
                    result.setError(error)
                }
            }
        }

        return try result.get()
    }

    func forwardGeocode(request: MapKitForwardGeocodeRequest) throws -> [MKMapItem] {
        guard let mkRequest = MKGeocodingRequest(addressString: request.address) else {
            throw MapKitProviderError.mapkitError("MapKit forward geocode request could not be created")
        }
        if let region = request.region {
            mkRequest.region = region
        }
        if let preferredLocale = request.preferredLocale {
            mkRequest.preferredLocale = preferredLocale
        }
        let result = MapKitSearchFetch.AsyncBridgeResult<[MKMapItem]>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit forward geocode") { complete in
            Task.detached {
                defer { complete() }
                do {
                    let mapItems = try await mkRequest.mapItems
                    result.setValue(mapItems)
                } catch {
                    result.setError(error)
                }
            }
        }

        return try result.get()
    }

    func calculateRoute(request: MapKitCalculateRouteRequest) throws -> MapKitCalculateRouteResult {
        let source = try mapItem(for: request.source)
        let destination = try mapItem(for: request.destination)
        let mkRequest = MKDirections.Request()
        mkRequest.source = source
        mkRequest.destination = destination
        mkRequest.transportType = request.transportType
        mkRequest.requestsAlternateRoutes = request.requestsAlternateRoutes
        mkRequest.departureDate = request.departureDate
        mkRequest.arrivalDate = request.arrivalDate
        mkRequest.tollPreference = request.tollPreference
        mkRequest.highwayPreference = request.highwayPreference

        let directions = MKDirections(request: mkRequest)
        let result = MapKitSearchFetch.AsyncBridgeResult<MKDirections.Response>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit directions") { complete in
            directions.calculate { response, error in
                if let error {
                    result.setError(error)
                } else if let response {
                    result.setValue(response)
                } else {
                    result.setError(MapKitProviderError.mapkitError("MapKit directions returned no response"))
                }
                complete()
            }
        }

        let response = try result.get()
        return MapKitCalculateRouteResult(
            source: MapKitPlaceNames.carryingName(from: source, onto: response.source, endpoint: request.source),
            destination: MapKitPlaceNames.carryingName(
                from: destination,
                onto: response.destination,
                endpoint: request.destination
            ),
            routes: response.routes.map(Self.routeData(from:))
        )
    }

    func estimateTravelTime(request: MapKitEstimateTravelTimeRequest) throws -> MapKitEstimateTravelTimeResult {
        let source = try mapItem(for: request.source)
        let destination = try mapItem(for: request.destination)
        let mkRequest = MKDirections.Request()
        mkRequest.source = source
        mkRequest.destination = destination
        mkRequest.transportType = request.transportType
        mkRequest.departureDate = request.departureDate
        mkRequest.arrivalDate = request.arrivalDate

        let directions = MKDirections(request: mkRequest)
        let result = MapKitSearchFetch.AsyncBridgeResult<MKDirections.ETAResponse>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit ETA") { complete in
            directions.calculateETA { response, error in
                if let error {
                    result.setError(error)
                } else if let response {
                    result.setValue(response)
                } else {
                    result.setError(MapKitProviderError.mapkitError("MapKit ETA returned no response"))
                }
                complete()
            }
        }

        let response = try result.get()
        return MapKitEstimateTravelTimeResult(
            source: MapKitPlaceNames.carryingName(from: source, onto: response.source, endpoint: request.source),
            destination: MapKitPlaceNames.carryingName(
                from: destination,
                onto: response.destination,
                endpoint: request.destination
            ),
            expectedTravelTime: response.expectedTravelTime,
            distance: response.distance,
            expectedArrivalDate: response.expectedArrivalDate,
            expectedDepartureDate: response.expectedDepartureDate,
            transportType: response.transportType
        )
    }

    func getPlace(request: MapKitGetPlaceRequest) throws -> MKMapItem {
        guard let identifier = MKMapItem.Identifier(rawValue: request.identifier) else {
            throw MapKitProviderError.invalidArguments("identifier is not a valid MapKit place identifier")
        }

        let mkRequest = MKMapItemRequest(mapItemIdentifier: identifier)
        let result = MapKitSearchFetch.AsyncBridgeResult<MKMapItem>()

        try MapKitSearchFetch.waitForCompletion(operation: "MapKit get place") { complete in
            Task.detached {
                defer { complete() }
                do {
                    let mapItem = try await mkRequest.mapItem
                    result.setValue(mapItem)
                } catch {
                    result.setError(error)
                }
            }
        }

        return try result.get()
    }

    func openNavigation(url: URL) throws {
        let result = MapKitSearchFetch.AsyncBridgeResult<Bool>()

        try MapKitSearchFetch.waitForCompletion(operation: "Apple Maps") { complete in
            MainActor.assumeIsolated {
                guard let applicationURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: "com.apple.Maps"
                ) else {
                    result.setError(MapKitProviderError.mapkitError("Failed to open Apple Maps"))
                    complete()
                    return
                }

                let configuration = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: applicationURL,
                    configuration: configuration
                ) { _, error in
                    if let error {
                        result.setError(
                            MapKitProviderError.mapkitError(
                                "Failed to open Apple Maps: \(error.localizedDescription)"
                            )
                        )
                    } else {
                        result.setValue(true)
                    }
                    complete()
                }
            }
        }

        _ = try result.get()
    }

    private func mapItem(for endpoint: MapKitRouteEndpoint) throws -> MKMapItem {
        if let identifier = endpoint.identifier {
            do {
                let item = try getPlace(request: MapKitGetPlaceRequest(identifier: identifier))
                return MapKitPlaceNames.labeled(item, endpoint: endpoint)
            } catch {
                guard endpoint.coordinate != nil else { throw error }
            }
        }

        guard let coordinate = endpoint.coordinate else {
            throw MapKitProviderError.invalidArguments(
                "route endpoint needs a coordinate or a MapKit place identifier"
            )
        }

        let item = MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
        if let name = endpoint.name, !MapKitPlaceNames.isPlaceholder(name) {
            item.name = name
            return item
        }
        if let geocoded = try? reverseGeocode(request: MapKitReverseGeocodeRequest(coordinate: coordinate)).first {
            if let name = geocoded.name, !MapKitPlaceNames.isPlaceholder(name) {
                item.name = name
            }
            if item.timeZone == nil {
                item.timeZone = geocoded.timeZone
            }
        }
        return item
    }
}

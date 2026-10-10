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
        let mkRequest = MKDirections.Request()
        mkRequest.source = mapItem(for: request.source.coordinate)
        mkRequest.destination = mapItem(for: request.destination.coordinate)
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
            source: response.source,
            destination: response.destination,
            routes: response.routes.map(Self.routeData(from:))
        )
    }

    func estimateTravelTime(request: MapKitEstimateTravelTimeRequest) throws -> MapKitEstimateTravelTimeResult {
        let mkRequest = MKDirections.Request()
        mkRequest.source = mapItem(for: request.source.coordinate)
        mkRequest.destination = mapItem(for: request.destination.coordinate)
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
            source: response.source,
            destination: response.destination,
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

    func openNavigation(request: MapKitOpenNavigationRequest) throws -> MapKitOpenNavigationResult {
        let source = mapItem(for: request.source.coordinate)
        let destination = mapItem(for: request.destination.coordinate)
        let launchOptions = Self.launchOptions(for: request.transportType)
        let opened = MKMapItem.openMaps(
            with: [source, destination],
            launchOptions: launchOptions
        )
        guard opened else {
            throw MapKitProviderError.mapkitError("Failed to open Apple Maps navigation")
        }

        return MapKitOpenNavigationResult(
            source: source,
            destination: destination,
            transportType: request.transportType,
            directionsMode: Self.directionsModeValue(for: request.transportType),
            opened: true
        )
    }

    private func mapItem(for coordinate: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
    }
}

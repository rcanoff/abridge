import CoreLocation
import Foundation
import MapKit

extension LiveMapKitStore {
    static func routeData(from route: MKRoute) -> MapKitRouteData {
        MapKitRouteData(
            name: route.name,
            advisoryNotices: route.advisoryNotices,
            distance: route.distance,
            expectedTravelTime: route.expectedTravelTime,
            transportType: route.transportType,
            polylineCoordinates: coordinates(from: route.polyline),
            polylineTitle: route.polyline.title,
            polylineSubtitle: route.polyline.subtitle,
            steps: route.steps.map(stepData(from:)),
            hasTolls: route.hasTolls,
            hasHighways: route.hasHighways
        )
    }

    static func stepData(from step: MKRoute.Step) -> MapKitRouteStepData {
        MapKitRouteStepData(
            instructions: step.instructions,
            notice: step.notice,
            distance: step.distance,
            transportType: step.transportType,
            polylineCoordinates: coordinates(from: step.polyline),
            polylineTitle: step.polyline.title,
            polylineSubtitle: step.polyline.subtitle
        )
    }

    static func launchOptions(for transportType: MKDirectionsTransportType) -> [String: Any]? {
        guard let directionsMode = directionsModeValue(for: transportType) else {
            return nil
        }

        return [MKLaunchOptionsDirectionsModeKey: directionsMode]
    }

    static func directionsModeValue(for transportType: MKDirectionsTransportType) -> String? {
        if transportType == .any {
            return nil
        }

        if transportType.contains(.automobile) {
            return MKLaunchOptionsDirectionsModeDriving
        }
        if transportType.contains(.walking) {
            return MKLaunchOptionsDirectionsModeWalking
        }
        if transportType.contains(.transit) {
            return MKLaunchOptionsDirectionsModeTransit
        }
        if transportType.contains(.cycling) {
            return MKLaunchOptionsDirectionsModeCycling
        }

        return MKLaunchOptionsDirectionsModeDriving
    }

    static func coordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        guard polyline.pointCount > 0 else { return [] }

        var coordinates = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: polyline.pointCount
        )
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: polyline.pointCount))
        return coordinates
    }
}

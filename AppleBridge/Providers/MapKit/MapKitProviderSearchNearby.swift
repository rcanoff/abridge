import Foundation
import MapKit

extension MapKitProvider {
    func searchNearby(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }

        do {
            let arguments = try parseSearchNearbyArguments(payloadJson)
            let result = try store.searchNearby(request: arguments)
            let payloadObject = MapKitSerialization.searchResponseJSONObject(
                mapItems: result.mapItems,
                boundingRegion: result.boundingRegion
            )
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseSearchNearbyArguments(_ payloadJson: String) throws -> MapKitSearchNearbyRequest {
        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let region = try requiredGeographicAnchor(in: dictionary)
        let pointOfInterestFilter = try optionalPOICategoryFilter(in: dictionary)

        return MapKitSearchNearbyRequest(
            region: region,
            pointOfInterestFilter: pointOfInterestFilter
        )
    }
}

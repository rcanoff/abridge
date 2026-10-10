import Foundation
import MapKit

extension MapKitProvider {
    func reverseGeocode(payloadJson: String) -> ProviderResponse {
        do {
            let arguments = try parseReverseGeocodeArguments(payloadJson)
            let mapItems = try store.reverseGeocode(request: arguments)
            let payloadObject = MapKitSerialization.reverseGeocodeResponseJSONObject(mapItems: mapItems)
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseReverseGeocodeArguments(_ payloadJson: String) throws -> MapKitReverseGeocodeRequest {
        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let coordinate = try requiredCoordinateArgument(in: dictionary)
        return MapKitReverseGeocodeRequest(coordinate: coordinate)
    }
}

import Foundation
import MapKit

extension MapKitProvider {
    func lookupPlace(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }

        do {
            let arguments = try parseLookupPlaceArguments(payloadJson)
            let mapItem = try store.lookupPlace(request: arguments)
            let payloadObject = MapKitSerialization.mapItemJSONObject(from: mapItem)
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseLookupPlaceArguments(_ payloadJson: String) throws -> MapKitLookupPlaceRequest {
        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        // Required non-empty identifier is schema-owned (Rust).
        let identifier = SchemaTrustedPayload.requiredString(dictionary, "identifier")
        return MapKitLookupPlaceRequest(identifier: identifier)
    }
}

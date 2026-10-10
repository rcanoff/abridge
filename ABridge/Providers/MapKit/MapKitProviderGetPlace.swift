import Foundation
import MapKit

extension MapKitProvider {
    func getPlace(payloadJson: String) -> ProviderResponse {
        do {
            let arguments = try parseGetPlaceArguments(payloadJson)
            let mapItem = try store.getPlace(request: arguments)
            let payloadObject = MapKitSerialization.mapItemJSONObject(from: mapItem)
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseGetPlaceArguments(_ payloadJson: String) throws -> MapKitGetPlaceRequest {
        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        // Required non-empty identifier is schema-owned (Rust).
        let identifier = SchemaTrustedPayload.requiredString(dictionary, "identifier")
        return MapKitGetPlaceRequest(identifier: identifier)
    }
}

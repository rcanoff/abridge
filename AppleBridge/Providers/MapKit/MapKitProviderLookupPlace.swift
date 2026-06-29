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
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MapKitProviderError.invalidArguments("identifier is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let identifier = try requiredIdentifierArgument(in: dictionary)
        return MapKitLookupPlaceRequest(identifier: identifier)
    }

    private func requiredIdentifierArgument(in dictionary: [String: Any]) throws -> String {
        guard dictionary.keys.contains("identifier") else {
            throw MapKitProviderError.invalidArguments("identifier is required")
        }

        if dictionary["identifier"] is NSNull {
            throw MapKitProviderError.invalidArguments("identifier is required")
        }

        guard let identifier = dictionary["identifier"] as? String else {
            throw MapKitProviderError.invalidArguments("identifier must be a string")
        }

        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MapKitProviderError.invalidArguments("identifier must not be empty")
        }

        return trimmed
    }
}

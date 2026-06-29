import Foundation
import MapKit

extension MapKitProvider {
    func forwardGeocode(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }

        do {
            let arguments = try parseForwardGeocodeArguments(payloadJson)
            let mapItems = try store.forwardGeocode(request: arguments)
            let payloadObject = MapKitSerialization.reverseGeocodeResponseJSONObject(mapItems: mapItems)
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseForwardGeocodeArguments(_ payloadJson: String) throws -> MapKitForwardGeocodeRequest {
        guard !payloadJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MapKitProviderError.invalidArguments("address is required")
        }

        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let address = try requiredAddressArgument(in: dictionary)
        let region = try optionalRegionArgument(in: dictionary)
        let preferredLocale = try optionalPreferredLocaleArgument(in: dictionary)
        return MapKitForwardGeocodeRequest(
            address: address,
            region: region,
            preferredLocale: preferredLocale
        )
    }

    private func requiredAddressArgument(in dictionary: [String: Any]) throws -> String {
        guard dictionary.keys.contains("address") else {
            throw MapKitProviderError.invalidArguments("address is required")
        }

        if dictionary["address"] is NSNull {
            throw MapKitProviderError.invalidArguments("address is required")
        }

        guard let address = dictionary["address"] as? String else {
            throw MapKitProviderError.invalidArguments("address must be a string")
        }

        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MapKitProviderError.invalidArguments("address must not be empty")
        }

        return trimmed
    }

    private func optionalPreferredLocaleArgument(in dictionary: [String: Any]) throws -> Locale? {
        guard dictionary.keys.contains("preferred_locale") else {
            return nil
        }

        if dictionary["preferred_locale"] is NSNull {
            return nil
        }

        guard let identifier = dictionary["preferred_locale"] as? String else {
            throw MapKitProviderError.invalidArguments("preferred_locale must be a string or null")
        }

        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MapKitProviderError.invalidArguments("preferred_locale must not be empty")
        }

        return Locale(identifier: trimmed)
    }
}
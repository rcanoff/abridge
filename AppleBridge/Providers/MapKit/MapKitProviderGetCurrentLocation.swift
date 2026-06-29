import Foundation

extension MapKitProvider {
    func getCurrentLocation(payloadJson: String) -> ProviderResponse {
        guard isLocationAuthorized else {
            return errorResponse(code: "permission_denied", message: "Location access not granted")
        }
        do {
            _ = try parseGetCurrentLocationArguments(payloadJson)
            let location = try store.getCurrentLocation()
            let payloadObject = MapKitSerialization.getCurrentLocationResponseJSONObject(location: location)
            let payload = try MapKitSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    private func parseGetCurrentLocationArguments(_ payloadJson: String) throws {
        let trimmed = payloadJson.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let data = trimmed.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }
        _ = try parseJSONObject(from: data)
    }
}

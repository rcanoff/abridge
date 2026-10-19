import Foundation

extension CoreLocationProvider {
    func getCurrentLocation(payloadJson: String) -> ProviderResponse {
        if let blocked = locationAccessError() {
            return blocked
        }
        do {
            _ = try parseGetCurrentLocationArguments(payloadJson)
            let location = try store.getCurrentLocation()
            let payloadObject = CoreLocationSerialization.getCurrentLocationResponseJSONObject(location: location)
            let payload = try CoreLocationSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch {
            return locationFailureResponse(for: error)
        }
    }

    private func parseGetCurrentLocationArguments(_ payloadJson: String) throws {
        let trimmed = payloadJson.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let data = trimmed.data(using: .utf8) else {
            throw CoreLocationProviderError.invalidArguments("Arguments must be valid UTF-8")
        }
        _ = try parseJSONObject(from: data)
    }
}

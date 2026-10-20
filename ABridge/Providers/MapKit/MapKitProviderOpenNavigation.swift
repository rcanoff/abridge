import Foundation

extension MapKitProvider {
    func openNavigation(payloadJson: String) -> ProviderResponse {
        do {
            let url = try parseOpenNavigationURL(payloadJson)
            try store.openNavigation(url: url)
            let payload = try MapKitSerialization.jsonString(from: ["opened": true])
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as MapKitProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "mapkit_error", message: error.localizedDescription)
        }
    }

    /// Rust builds the directions URL. Swift still refuses anything that is not an
    /// `https://maps.apple.com/directions` URL so the store never opens another address.
    private func parseOpenNavigationURL(_ payloadJson: String) throws -> URL {
        guard let data = payloadJson.data(using: .utf8) else {
            throw MapKitProviderError.invalidArguments("Arguments must be valid UTF-8")
        }

        let dictionary = try parseJSONObject(from: data)
        let rawURL = SchemaTrustedPayload.requiredString(dictionary, "url")
        guard let url = URL(string: rawURL), Self.isAppleMapsDirectionsURL(url) else {
            throw MapKitProviderError.invalidArguments(
                "url must be an https://maps.apple.com/directions URL"
            )
        }
        return url
    }

    private static func isAppleMapsDirectionsURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" &&
            url.host?.lowercased() == "maps.apple.com" &&
            url.path == "/directions"
    }
}

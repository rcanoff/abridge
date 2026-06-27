import Foundation

final class AppleProviderBridge: ProviderBridge, @unchecked Sendable {
    func callProvider(request _: ProviderRequest) -> ProviderResponse {
        ProviderResponse(
            ok: false,
            payloadJson: "{}",
            errorJson: #"{"code":"not_implemented"}"#
        )
    }
}

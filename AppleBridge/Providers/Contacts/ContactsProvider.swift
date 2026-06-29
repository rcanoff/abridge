import Foundation

@MainActor
struct ContactsProvider {
    func handle(operation: String, payloadJson _: String) -> ProviderResponse {
        let error = #"{"code":"unknown_operation","message":"Unknown contacts operation: \#(operation)"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: error)
    }
}

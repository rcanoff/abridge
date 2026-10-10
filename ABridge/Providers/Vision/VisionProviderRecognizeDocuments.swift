import Foundation
import Vision

extension VisionProvider {
    func recognizeDocuments(payloadJson: String) async -> ProviderResponse {
        do {
            let arguments = try parseRecognizeDocumentsArguments(payloadJson)
            let result = try await store.recognizeDocuments(request: arguments)
            let payloadObject = try VisionSerialization.recognizeDocumentsResponseJSONObject(
                observations: result.observations,
                segmentation: result.segmentation,
                maximumCandidateCount: arguments.maximumCandidateCount
            )
            let payload = try VisionSerialization.jsonString(from: payloadObject)
            return ProviderResponse(ok: true, payloadJson: payload, errorJson: nil)
        } catch let error as VisionProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "vision_error", message: error.localizedDescription)
        }
    }
}

import Foundation
import Vision

extension VisionProvider {
    func recognizeDocuments(payloadJson: String) async -> ProviderResponse {
        do {
            let arguments = try parseRecognizeDocumentsArguments(payloadJson)
            let outcome = try await store.recognizeDocuments(request: arguments)
            let payloadObject = try attachingPdfPage(
                VisionSerialization.recognizeDocumentsResponseJSONObject(
                    observations: outcome.value.observations,
                    segmentation: outcome.value.segmentation,
                    maximumCandidateCount: arguments.maximumCandidateCount
                ),
                pdf: outcome.pdf
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

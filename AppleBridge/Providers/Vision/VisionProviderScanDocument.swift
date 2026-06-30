import Foundation
import Vision

extension VisionProvider {
    func scanDocument(payloadJson: String) -> ProviderResponse {
        do {
            let arguments = try parseScanDocumentArguments(payloadJson)
            let result = try store.scanDocument(request: arguments)
            let payloadObject = VisionSerialization.scanDocumentResponseJSONObject(
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

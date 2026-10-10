import Foundation

extension VisionProvider {
    /// FFI entry point. The whole operation runs on the Vision worker thread: argument parsing, the
    /// Vision request, and serialization. Vision computes some result properties (detected data in
    /// recognized text) lazily on first read, so serialization does Vision work too.
    func handle(operation: String, payloadJson: String) -> ProviderResponse {
        do {
            return try VisionAsyncBridge.perform(operation: "Vision \(operation)") { [self] in
                await route(operation: operation, payloadJson: payloadJson)
            }
        } catch let error as VisionProviderError {
            return providerErrorResponse(from: error)
        } catch {
            return errorResponse(code: "vision_error", message: error.localizedDescription)
        }
    }

    private func route(operation: String, payloadJson: String) async -> ProviderResponse {
        switch operation {
        case "recognize_text":
            await recognizeText(payloadJson: payloadJson)
        case "recognize_documents":
            await recognizeDocuments(payloadJson: payloadJson)
        case "detect_barcodes":
            await detectBarcodes(payloadJson: payloadJson)
        case "detect_face_landmarks":
            await detectFaceLandmarks(payloadJson: payloadJson)
        default:
            errorResponse(code: "unknown_operation", message: "Unknown vision operation: \(operation)")
        }
    }
}

@testable import AppleBridge
import Vision

@MainActor
final class MockVisionStore: VisionStoreing {
    var observations: [VNRecognizedTextObservation] = []
    var error: Error?
    private(set) var lastRequest: VisionRecognizeTextRequest?

    func recognizeText(request: VisionRecognizeTextRequest) throws -> [VNRecognizedTextObservation] {
        lastRequest = request
        if let error {
            throw error
        }
        return observations
    }
}
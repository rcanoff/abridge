@testable import ABridge
import Vision

final class MockVisionStore: VisionStoreing, @unchecked Sendable {
    var observations: [VNRecognizedTextObservation] = []
    var recognizeDocumentsResult = VisionRecognizeDocumentsResult(observations: [], segmentation: nil)
    var detectBarcodesObservations: [BarcodeObservation] = []
    var faceObservations: [VNFaceObservation] = []
    var error: Error?
    private(set) var lastRequest: VisionRecognizeTextRequest?
    private(set) var lastRecognizeDocumentsRequest: VisionRecognizeDocumentsRequest?
    private(set) var lastDetectBarcodesRequest: VisionDetectBarcodesRequest?
    private(set) var lastDetectFaceLandmarksRequest: VisionDetectFaceLandmarksRequest?

    func recognizeText(request: VisionRecognizeTextRequest) async throws -> [VNRecognizedTextObservation] {
        lastRequest = request
        if let error {
            throw error
        }
        return observations
    }

    func recognizeDocuments(request: VisionRecognizeDocumentsRequest) async throws -> VisionRecognizeDocumentsResult {
        lastRecognizeDocumentsRequest = request
        if let error {
            throw error
        }
        return recognizeDocumentsResult
    }

    func detectBarcodes(request: VisionDetectBarcodesRequest) async throws -> [BarcodeObservation] {
        lastDetectBarcodesRequest = request
        if let error {
            throw error
        }
        return detectBarcodesObservations
    }

    func detectFaceLandmarks(request: VisionDetectFaceLandmarksRequest) async throws -> [VNFaceObservation] {
        lastDetectFaceLandmarksRequest = request
        if let error {
            throw error
        }
        return faceObservations
    }
}

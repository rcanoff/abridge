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
    /// Raster passed to Vision after a PDF page is rendered. Images keep their original bytes.
    private(set) var lastPreparedImageData: Data?

    func recognizeText(
        request: VisionRecognizeTextRequest
    ) async throws -> VisionStoreResult<[VisionRecognizedText]> {
        let prepared = try VisionPdf.prepare(data: request.imageData, page: request.page)
        lastRequest = request
        lastPreparedImageData = prepared.imageData
        if let error {
            throw error
        }
        return VisionStoreResult(
            value: observations.map(VisionRecognizedText.init),
            pdf: prepared.pdf
        )
    }

    func recognizeDocuments(
        request: VisionRecognizeDocumentsRequest
    ) async throws -> VisionStoreResult<VisionRecognizeDocumentsResult> {
        let prepared = try VisionPdf.prepare(data: request.imageData, page: request.page)
        lastRecognizeDocumentsRequest = request
        lastPreparedImageData = prepared.imageData
        if let error {
            throw error
        }
        return VisionStoreResult(value: recognizeDocumentsResult, pdf: prepared.pdf)
    }

    func detectBarcodes(
        request: VisionDetectBarcodesRequest
    ) async throws -> VisionStoreResult<[BarcodeObservation]> {
        let prepared = try VisionPdf.prepare(data: request.imageData, page: request.page)
        lastDetectBarcodesRequest = request
        lastPreparedImageData = prepared.imageData
        if let error {
            throw error
        }
        return VisionStoreResult(value: detectBarcodesObservations, pdf: prepared.pdf)
    }

    func detectFaceLandmarks(
        request: VisionDetectFaceLandmarksRequest
    ) async throws -> VisionStoreResult<[VNFaceObservation]> {
        let prepared = try VisionPdf.prepare(data: request.imageData, page: request.page)
        lastDetectFaceLandmarksRequest = request
        lastPreparedImageData = prepared.imageData
        if let error {
            throw error
        }
        return VisionStoreResult(value: faceObservations, pdf: prepared.pdf)
    }
}

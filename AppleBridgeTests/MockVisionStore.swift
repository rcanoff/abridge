@testable import AppleBridge
import Vision

@MainActor
final class MockVisionStore: VisionStoreing {
    var observations: [VNRecognizedTextObservation] = []
    var scanDocumentResult = VisionScanDocumentResult(observations: [], segmentation: nil)
    var barcodeObservations: [VNBarcodeObservation] = []
    var error: Error?
    private(set) var lastRequest: VisionRecognizeTextRequest?
    private(set) var lastScanDocumentRequest: VisionScanDocumentRequest?
    private(set) var lastReadQrCodeRequest: VisionReadQrCodeRequest?

    func recognizeText(request: VisionRecognizeTextRequest) throws -> [VNRecognizedTextObservation] {
        lastRequest = request
        if let error {
            throw error
        }
        return observations
    }

    func scanDocument(request: VisionScanDocumentRequest) throws -> VisionScanDocumentResult {
        lastScanDocumentRequest = request
        if let error {
            throw error
        }
        return scanDocumentResult
    }

    func readQrCode(request: VisionReadQrCodeRequest) throws -> [VNBarcodeObservation] {
        lastReadQrCodeRequest = request
        if let error {
            throw error
        }
        return barcodeObservations
    }
}

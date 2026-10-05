@testable import ABridge
import Vision

@MainActor
final class MockVisionStore: VisionStoreing {
    var observations: [VNRecognizedTextObservation] = []
    var scanDocumentResult = VisionScanDocumentResult(observations: [], segmentation: nil)
    var readQrCodeObservations: [VNBarcodeObservation] = []
    var detectBarcodesObservations: [BarcodeObservation] = []
    var faceObservations: [VNFaceObservation] = []
    var error: Error?
    private(set) var lastRequest: VisionRecognizeTextRequest?
    private(set) var lastScanDocumentRequest: VisionScanDocumentRequest?
    private(set) var lastReadQrCodeRequest: VisionReadQrCodeRequest?
    private(set) var lastDetectBarcodesRequest: VisionDetectBarcodesRequest?
    private(set) var lastDetectFacesRequest: VisionDetectFacesRequest?

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
        return readQrCodeObservations
    }

    func detectBarcodes(request: VisionDetectBarcodesRequest) throws -> [BarcodeObservation] {
        lastDetectBarcodesRequest = request
        if let error {
            throw error
        }
        return detectBarcodesObservations
    }

    func detectFaces(request: VisionDetectFacesRequest) throws -> [VNFaceObservation] {
        lastDetectFacesRequest = request
        if let error {
            throw error
        }
        return faceObservations
    }
}

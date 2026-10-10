import CoreGraphics
import Vision

struct VisionRecognizeTextRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let recognitionLanguages: [String]?
    let customWords: [String]?
    let recognitionLevel: VNRequestTextRecognitionLevel
    let usesLanguageCorrection: Bool?
    let automaticallyDetectsLanguage: Bool?
    let minimumTextHeight: Float?
    let revision: Int?
    let preferBackgroundProcessing: Bool?
    let regionOfInterest: CGRect?
    let maxCandidateCount: Int
}

struct VisionRecognizeDocumentsRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: RecognizeDocumentsRequest.Revision?
    let regionOfInterest: NormalizedRect?
    let textRecognitionOptions: RecognizeDocumentsRequest.TextRecognitionOptions?
    let barcodeDetectionOptions: RecognizeDocumentsRequest.BarcodeDetectionOptions?
    let includeSegmentation: Bool
    let maximumCandidateCount: Int
}

struct VisionRecognizeDocumentsResult: Equatable {
    let observations: [DocumentObservation]
    let segmentation: DetectedDocumentObservation?
}

struct VisionDetectBarcodesRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: DetectBarcodesRequest.Revision?
    let regionOfInterest: NormalizedRect?
    let symbologies: [BarcodeSymbology]?
    let coalesceCompositeSymbologies: Bool?
}

struct VisionDetectFaceLandmarksRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: Int?
    let regionOfInterest: CGRect?
    let constellation: VNRequestFaceLandmarksConstellation
}

/// Called only on the Vision worker thread (see `VisionAsyncBridge`).
protocol VisionStoreing: Sendable {
    func recognizeText(request: VisionRecognizeTextRequest) async throws -> [VNRecognizedTextObservation]
    func recognizeDocuments(request: VisionRecognizeDocumentsRequest) async throws -> VisionRecognizeDocumentsResult
    func detectBarcodes(request: VisionDetectBarcodesRequest) async throws -> [BarcodeObservation]
    func detectFaceLandmarks(request: VisionDetectFaceLandmarksRequest) async throws -> [VNFaceObservation]
}

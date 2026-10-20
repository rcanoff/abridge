import CoreGraphics
import Vision

struct VisionStoreResult<Value> {
    let value: Value
    let pdf: VisionPdfInfo?
}

/// One recognized line. Geometry is in whole-image Vision coordinates, including after tiling.
struct VisionRecognizedText {
    let observation: VNRecognizedTextObservation
    let boundingBox: CGRect
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint

    init(observation: VNRecognizedTextObservation) {
        self.observation = observation
        boundingBox = observation.boundingBox
        topLeft = observation.topLeft
        topRight = observation.topRight
        bottomLeft = observation.bottomLeft
        bottomRight = observation.bottomRight
    }

    init(
        observation: VNRecognizedTextObservation,
        boundingBox: CGRect,
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint
    ) {
        self.observation = observation
        self.boundingBox = boundingBox
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }
}

struct VisionRecognizeTextRequest: Equatable {
    let imageData: Data
    /// 1-based PDF page. Images use 1.
    let page: Int
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
    /// 1-based PDF page. Images use 1.
    let page: Int
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
    /// 1-based PDF page. Images use 1.
    let page: Int
    let orientation: CGImagePropertyOrientation?
    let revision: DetectBarcodesRequest.Revision?
    let regionOfInterest: NormalizedRect?
    let symbologies: [BarcodeSymbology]?
    let coalesceCompositeSymbologies: Bool?
}

struct VisionDetectFaceLandmarksRequest: Equatable {
    let imageData: Data
    /// 1-based PDF page. Images use 1.
    let page: Int
    let orientation: CGImagePropertyOrientation?
    let revision: Int?
    let regionOfInterest: CGRect?
    let constellation: VNRequestFaceLandmarksConstellation
}

/// Called only on the Vision worker thread (see `VisionAsyncBridge`).
protocol VisionStoreing: Sendable {
    func recognizeText(request: VisionRecognizeTextRequest) async throws
        -> VisionStoreResult<[VisionRecognizedText]>
    func recognizeDocuments(
        request: VisionRecognizeDocumentsRequest
    ) async throws -> VisionStoreResult<VisionRecognizeDocumentsResult>
    func detectBarcodes(request: VisionDetectBarcodesRequest) async throws -> VisionStoreResult<[BarcodeObservation]>
    func detectFaceLandmarks(
        request: VisionDetectFaceLandmarksRequest
    ) async throws -> VisionStoreResult<[VNFaceObservation]>
}

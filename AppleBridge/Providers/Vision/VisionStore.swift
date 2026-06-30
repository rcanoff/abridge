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

struct VisionScanDocumentRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: RecognizeDocumentsRequest.Revision?
    let regionOfInterest: NormalizedRect?
    let textRecognitionOptions: RecognizeDocumentsRequest.TextRecognitionOptions?
    let barcodeDetectionOptions: RecognizeDocumentsRequest.BarcodeDetectionOptions?
    let includeSegmentation: Bool
    let maximumCandidateCount: Int
}

struct VisionScanDocumentResult: Equatable {
    let observations: [DocumentObservation]
    let segmentation: DetectedDocumentObservation?
}

struct VisionReadQrCodeRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: Int?
    let regionOfInterest: CGRect?
    let coalesceCompositeSymbologies: Bool?
}

struct VisionDetectBarcodesRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: DetectBarcodesRequest.Revision?
    let regionOfInterest: NormalizedRect?
    let symbologies: [BarcodeSymbology]?
    let coalesceCompositeSymbologies: Bool?
}

struct VisionDetectFacesRequest: Equatable {
    let imageData: Data
    let orientation: CGImagePropertyOrientation?
    let revision: Int?
    let regionOfInterest: CGRect?
    let constellation: VNRequestFaceLandmarksConstellation
}

@MainActor
protocol VisionStoreing {
    func recognizeText(request: VisionRecognizeTextRequest) throws -> [VNRecognizedTextObservation]
    func scanDocument(request: VisionScanDocumentRequest) throws -> VisionScanDocumentResult
    func readQrCode(request: VisionReadQrCodeRequest) throws -> [VNBarcodeObservation]
    func detectBarcodes(request: VisionDetectBarcodesRequest) throws -> [BarcodeObservation]
    func detectFaces(request: VisionDetectFacesRequest) throws -> [VNFaceObservation]
}

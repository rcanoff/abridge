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

@MainActor
protocol VisionStoreing {
    func recognizeText(request: VisionRecognizeTextRequest) throws -> [VNRecognizedTextObservation]
}
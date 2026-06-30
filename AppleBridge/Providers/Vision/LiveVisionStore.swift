import CoreGraphics
import Foundation
import ImageIO
import Vision

@MainActor
struct LiveVisionStore: VisionStoreing {
    func recognizeText(request: VisionRecognizeTextRequest) throws -> [VNRecognizedTextObservation] {
        let cgImage = try decodeCGImage(from: request.imageData)
        let orientation = request.orientation ?? .up

        let recognizeRequest = VNRecognizeTextRequest()
        if let recognitionLanguages = request.recognitionLanguages {
            recognizeRequest.recognitionLanguages = recognitionLanguages
        }
        if let customWords = request.customWords {
            recognizeRequest.customWords = customWords
        }
        recognizeRequest.recognitionLevel = request.recognitionLevel
        if let usesLanguageCorrection = request.usesLanguageCorrection {
            recognizeRequest.usesLanguageCorrection = usesLanguageCorrection
        }
        if let automaticallyDetectsLanguage = request.automaticallyDetectsLanguage {
            recognizeRequest.automaticallyDetectsLanguage = automaticallyDetectsLanguage
        }
        if let minimumTextHeight = request.minimumTextHeight {
            recognizeRequest.minimumTextHeight = minimumTextHeight
        }
        if let revision = request.revision {
            recognizeRequest.revision = revision
        }
        if let preferBackgroundProcessing = request.preferBackgroundProcessing {
            recognizeRequest.preferBackgroundProcessing = preferBackgroundProcessing
        }
        if let regionOfInterest = request.regionOfInterest {
            recognizeRequest.regionOfInterest = regionOfInterest
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([recognizeRequest])
        } catch {
            throw VisionProviderError.visionError(error.localizedDescription)
        }

        return recognizeRequest.results ?? []
    }

    private func decodeCGImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw VisionProviderError.invalidArguments("image_data could not be decoded as an image")
        }
        return image
    }
}
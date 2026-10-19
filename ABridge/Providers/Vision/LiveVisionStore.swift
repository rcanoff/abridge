import CoreGraphics
import Foundation
import ImageIO
import Vision

struct LiveVisionStore: VisionStoreing {
    func detectBarcodes(request: VisionDetectBarcodesRequest) async throws -> VisionStoreResult<[BarcodeObservation]> {
        let prepared = try VisionPdf.prepare(data: request.imageData, page: request.page)
        let imageSource = try imageSource(from: prepared.imageData)
        let orientation = request.orientation ?? orientationFromImageSource(imageSource)
        let handler = ImageRequestHandler(prepared.imageData, orientation: orientation)
        let observations = try await performVision {
            try await handler.perform(makeDetectBarcodesRequest(from: request))
        }
        return VisionStoreResult(value: observations, pdf: prepared.pdf)
    }

    private func makeDetectBarcodesRequest(from request: VisionDetectBarcodesRequest) -> DetectBarcodesRequest {
        var detectRequest = DetectBarcodesRequest(request.revision)
        if let regionOfInterest = request.regionOfInterest {
            detectRequest.regionOfInterest = regionOfInterest
        }
        if let symbologies = request.symbologies {
            detectRequest.symbologies = symbologies
        }
        if let coalesceCompositeSymbologies = request.coalesceCompositeSymbologies {
            detectRequest.coalescesCompositeSymbologies = coalesceCompositeSymbologies
        }
        return detectRequest
    }

    func recognizeDocuments(
        request: VisionRecognizeDocumentsRequest
    ) async throws -> VisionStoreResult<VisionRecognizeDocumentsResult> {
        let prepared = try VisionPdf.prepare(data: request.imageData, page: request.page)
        let imageSource = try imageSource(from: prepared.imageData)
        let orientation = request.orientation ?? orientationFromImageSource(imageSource)
        let handler = ImageRequestHandler(prepared.imageData, orientation: orientation)

        let observations = try await performVision {
            try await handler.perform(makeRecognizeDocumentsRequest(from: request))
        }
        let segmentation: DetectedDocumentObservation? = if request.includeSegmentation {
            try await performVision { try await handler.perform(DetectDocumentSegmentationRequest()) }
        } else {
            nil
        }

        return VisionStoreResult(
            value: VisionRecognizeDocumentsResult(observations: observations, segmentation: segmentation),
            pdf: prepared.pdf
        )
    }

    private func makeRecognizeDocumentsRequest(
        from request: VisionRecognizeDocumentsRequest
    ) -> RecognizeDocumentsRequest {
        var recognizeRequest = RecognizeDocumentsRequest(request.revision)
        if let regionOfInterest = request.regionOfInterest {
            recognizeRequest.regionOfInterest = regionOfInterest
        }
        if let textRecognitionOptions = request.textRecognitionOptions {
            recognizeRequest.textRecognitionOptions = textRecognitionOptions
        }
        if let barcodeDetectionOptions = request.barcodeDetectionOptions {
            recognizeRequest.barcodeDetectionOptions = barcodeDetectionOptions
        }
        return recognizeRequest
    }

    /// Maps framework errors to `vision_error`; argument errors pass through.
    private func performVision<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as VisionProviderError {
            throw error
        } catch {
            throw VisionProviderError.visionError(error.localizedDescription)
        }
    }

    func detectFaceLandmarks(
        request: VisionDetectFaceLandmarksRequest
    ) async throws -> VisionStoreResult<[VNFaceObservation]> {
        let prepared = try VisionPdf.prepare(data: request.imageData, page: request.page)
        let imageSource = try imageSource(from: prepared.imageData)
        let cgImage = try decodeCGImage(from: imageSource)
        let orientation = request.orientation ?? orientationFromImageSource(imageSource)

        let detectRequest = VNDetectFaceLandmarksRequest()
        if let revision = request.revision {
            detectRequest.revision = revision
        }
        if let regionOfInterest = request.regionOfInterest {
            detectRequest.regionOfInterest = regionOfInterest
        }
        detectRequest.constellation = request.constellation

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        do {
            try handler.perform([detectRequest])
        } catch {
            throw VisionProviderError.visionError(error.localizedDescription)
        }

        return VisionStoreResult(value: detectRequest.results ?? [], pdf: prepared.pdf)
    }

    func recognizeText(
        request: VisionRecognizeTextRequest
    ) async throws -> VisionStoreResult<[VNRecognizedTextObservation]> {
        let prepared = try VisionPdf.prepare(data: request.imageData, page: request.page)
        let imageSource = try imageSource(from: prepared.imageData)
        let cgImage = try decodeCGImage(from: imageSource)
        let orientation = request.orientation ?? orientationFromImageSource(imageSource)

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

        return VisionStoreResult(value: recognizeRequest.results ?? [], pdf: prepared.pdf)
    }

    private func imageSource(from data: Data) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw VisionProviderError.invalidArguments("image_data could not be decoded as an image")
        }
        return source
    }

    private func decodeCGImage(from source: CGImageSource) throws -> CGImage {
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw VisionProviderError.invalidArguments("image_data could not be decoded as an image")
        }
        return image
    }

    private func orientationFromImageSource(_ source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let orientationValue = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: orientationValue)
        else {
            return .up
        }
        return orientation
    }
}

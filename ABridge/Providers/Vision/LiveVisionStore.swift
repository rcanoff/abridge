import CoreGraphics
import CoreImage
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
    ) async throws -> VisionStoreResult<[VisionRecognizedText]> {
        let prepared = try VisionPdf.prepare(data: request.imageData, page: request.page)
        let imageSource = try imageSource(from: prepared.imageData)
        let cgImage = try decodeCGImage(from: imageSource)
        let orientation = request.orientation ?? orientationFromImageSource(imageSource)
        let image = try upright(cgImage, orientation: orientation)
        let lines = try recognizeTextLines(in: image, request: request)
        return VisionStoreResult(value: lines, pdf: prepared.pdf)
    }

    /// Tall or wide images are recognized per tile. Boxes are mapped back to the whole image, and a
    /// line is kept only from the tile whose core contains its center.
    private func recognizeTextLines(
        in image: CGImage,
        request: VisionRecognizeTextRequest
    ) throws -> [VisionRecognizedText] {
        let tiles = VisionTextTiles.tiles(width: image.width, height: image.height)
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var lines: [VisionRecognizedText] = []
        for tile in tiles {
            let crop = tile.crop.intersection(bounds)
            guard crop.width >= 1, crop.height >= 1 else { continue }
            let region = request.regionOfInterest.flatMap {
                VisionTextTiles.localRegion($0, crop: crop, imageWidth: image.width, imageHeight: image.height)
            }
            if request.regionOfInterest != nil, region == nil {
                continue
            }
            let piece: CGImage
            if crop.origin == .zero, Int(crop.width) == image.width, Int(crop.height) == image.height {
                piece = image
            } else {
                guard let cropped = copy(image, crop: crop) else { continue }
                piece = cropped
            }
            let recognizeRequest = makeRecognizeTextRequest(from: request, regionOfInterest: region)
            let handler = VNImageRequestHandler(cgImage: piece, orientation: .up, options: [:])
            do {
                try handler.perform([recognizeRequest])
            } catch {
                throw VisionProviderError.visionError(error.localizedDescription)
            }
            for observation in recognizeRequest.results ?? [] {
                guard let line = placedLine(observation, tile: tile, crop: crop, image: image) else { continue }
                lines.append(line)
            }
        }
        return lines
    }

    private func placedLine(
        _ observation: VNRecognizedTextObservation,
        tile: VisionTextTiles.Tile,
        crop: CGRect,
        image: CGImage
    ) -> VisionRecognizedText? {
        let box = VisionTextTiles.map(
            box: observation.boundingBox,
            crop: crop,
            imageWidth: image.width,
            imageHeight: image.height
        )
        guard tile.contains(center: CGPoint(x: box.midX, y: box.midY)) else { return nil }
        func mapPoint(_ point: CGPoint) -> CGPoint {
            VisionTextTiles.map(point: point, crop: crop, imageWidth: image.width, imageHeight: image.height)
        }
        return VisionRecognizedText(
            observation: observation,
            boundingBox: box,
            topLeft: mapPoint(observation.topLeft),
            topRight: mapPoint(observation.topRight),
            bottomLeft: mapPoint(observation.bottomLeft),
            bottomRight: mapPoint(observation.bottomRight)
        )
    }

    private func makeRecognizeTextRequest(
        from request: VisionRecognizeTextRequest,
        regionOfInterest: CGRect?
    ) -> VNRecognizeTextRequest {
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
        if let regionOfInterest {
            recognizeRequest.regionOfInterest = regionOfInterest
        }
        return recognizeRequest
    }

    /// `cropping(to:)` can leave a sub-image Vision reads from the wrong origin. Draw the crop into a new bitmap.
    private func copy(_ image: CGImage, crop: CGRect) -> CGImage? {
        let width = Int(crop.width.rounded())
        let height = Int(crop.height.rounded())
        guard width >= 1, height >= 1 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.draw(
            image,
            in: CGRect(
                x: -crop.minX,
                y: -(CGFloat(image.height) - crop.maxY),
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        return context.makeImage()
    }

    /// Vision's normalized boxes follow the oriented image. Draw that orientation out so tile crops match.
    private func upright(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> CGImage {
        guard orientation != .up else { return image }
        let source = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation.rawValue))
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let rendered = context.createCGImage(source, from: source.extent) else {
            throw VisionProviderError.visionError("image_data could not be decoded as an image")
        }
        return rendered
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

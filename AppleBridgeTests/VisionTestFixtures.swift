@testable import AppleBridge
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum VisionTestFixtures {
    static let sampleText = "TEST"

    static func sampleTextImageData() throws -> Data {
        let width = 240
        let height = 80
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VisionProviderError.visionError("Failed to create sample image context")
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let attributed = NSAttributedString(string: sampleText, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 24, y: 16)
        CTLineDraw(line, context)

        guard let cgImage = context.makeImage() else {
            throw VisionProviderError.visionError("Failed to render sample image")
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw VisionProviderError.visionError("Failed to create PNG destination")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VisionProviderError.visionError("Failed to finalize sample PNG")
        }
        return data as Data
    }

    @MainActor
    static func sampleRecognizedTextObservations() throws -> [VNRecognizedTextObservation] {
        let imageData = try sampleTextImageData()
        let store = LiveVisionStore()
        let request = VisionRecognizeTextRequest(
            imageData: imageData,
            orientation: nil,
            recognitionLanguages: nil,
            customWords: nil,
            recognitionLevel: .accurate,
            usesLanguageCorrection: nil,
            automaticallyDetectsLanguage: nil,
            minimumTextHeight: nil,
            revision: nil,
            preferBackgroundProcessing: nil,
            regionOfInterest: nil,
            maxCandidateCount: 1
        )
        return try store.recognizeText(request: request)
    }
}
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

    /// Pre-archived `VNRecognizedTextObservation` fixture generated from a sample image.
    /// Unit tests load this deterministically instead of invoking live Vision OCR.
    private static let archivedRecognizedTextObservationsBase64 =
        "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEDgLDBI1O0JGSVJTVGBhYmNkZWZpdXaDiZGSOJaanqKjp6qrr7Kzt7q7v8PEyMvM0NPU2Nvc4OPk51UkbnVsbNINDg8RWk5TLm9iamVjdHNWJGNsYXNzoRCAAoA23xASExQVFhcYGRoOGxwdHh8gISIjJCUmJygpKissLS4vMDExMjM0VHV1aWRTVFJYWmNvbmZpZGVuY2VTQkxZU0JSWFNUUllbdGV4dE9iamVjdHNTVExYU0JSWVl0aW1lUmFuZ2VUdGV4dFNCTFhdVk5PYnNlcnZhdGlvbl8QG1ZORGV0ZWN0ZWRPYmplY3RPYnNlcnZhdGlvbldyZXF1ZXN0U1RMWVdncm91cElkgAUjP993d3laI6EiP4AAACM/mZmZqnkcQCM/33d3eVojoSM/3MzMzdrE9oAUIz4eKsKZmZmagDcjP5mZmap5HECAB4ATIz4eKsKZmZmaEACAAyM/3MzMzdrE9oAA0zYONzg5OlNyZXZUY29kZRADgAQSUlR4dNI8PT4/WiRjbGFzc25hbWVYJGNsYXNzZXNfEBJWTlJlcXVlc3RTcGVjaWZpZXKiQEFfEBJWTlJlcXVlc3RTcGVjaWZpZXJYTlNPYmplY3TSQw5ERVxOUy51dWlkYnl0ZXNPEBCGjB3ZWANI14mubIQGaCRagAbSPD1HSFZOU1VVSUSiR0HTSg0OS05RV05TLmtleXOiTE2ACIAJok9QgAqAEoARVXN0YXJ0WGR1cmF0aW9u00oNDlVaUaRWV1hZgAuADIANgA6kW1xbXIAPgBCAD4AQgBFVZmxhZ3NVdmFsdWVZdGltZXNjYWxlVWVwb2NoEAEQANI8PWdoXE5TRGljdGlvbmFyeaJnQdNKDQ5qb1GkVldYWYALgAyADYAOpFtcW1yAD4AQgA+AEIARVFRFU1TSDQ53Eap4eXp7fH1+f4CBgBWAG4AegCGAJIAngCqALYAwgDOANtOEDoWGh4hYY3JPdXRwdXRfEA9yZXF1ZXN0UmV2aXNpb26AFoAagBnUDoqLjI2Oj5BfEBRDUk91dHB1dEVuY29kaW5nRGF0YV8QJENST3V0cHV0RW5j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"

    @MainActor
    static func sampleRecognizedTextObservations() throws -> [VNRecognizedTextObservation] {
        guard let archivedData = Data(base64Encoded: archivedRecognizedTextObservationsBase64) else {
            throw VisionProviderError.serializationFailed
        }
        guard let observations = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(archivedData)
            as? [VNRecognizedTextObservation],
            observations.isEmpty == false
        else {
            throw VisionProviderError.serializationFailed
        }
        return observations
    }
}
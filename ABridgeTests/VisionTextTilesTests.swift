@testable import ABridge
import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import Vision

@Suite("Vision text tiles")
struct VisionTextTilesTests {
    @Test
    func aModerateImageStaysOneTile() {
        let tiles = VisionTextTiles.tiles(width: 400, height: 500)
        #expect(tiles.count == 1)
        #expect(tiles[0].contains(center: CGPoint(x: 0.5, y: 0.5)))
    }

    @Test
    func tallTilesCoverEveryLineOnceAndStayNearlySquare() {
        let width = 200
        let height = 1200
        let tiles = VisionTextTiles.tiles(width: width, height: height)
        #expect(tiles.count >= 3)
        let limit = Int((CGFloat(width) * VisionTextTiles.tileLongMultiple).rounded(.up))
        for tile in tiles {
            #expect(Int(tile.crop.height) <= limit)
            #expect(Int(tile.crop.width) == width)
        }

        var kept = 0
        for lineTop in stride(from: 8, to: height - 8, by: 24) {
            let center = CGPoint(x: 0.5, y: (CGFloat(height) - CGFloat(lineTop)) / CGFloat(height))
            let owners = tiles.filter { $0.contains(center: center) }
            #expect(owners.count == 1, "line at \(lineTop) owned by \(owners.count)")
            kept += 1
        }
        #expect(kept == 50)
    }

    @Test
    func aWideImageIsNotTiledAndATallImageIs() {
        let wide = VisionTextTiles.tiles(width: 1200, height: 200)
        #expect(wide.count == 1)
        #expect(wide[0].crop == CGRect(x: 0, y: 0, width: 1200, height: 200))

        let boundary = VisionTextTiles.tiles(width: 200, height: 300)
        #expect(boundary.count == 1)

        let tall = VisionTextTiles.tiles(width: 200, height: 1200)
        #expect(tall.count > 1)
        for tile in tall {
            #expect(tile.vertical)
            #expect(Int(tile.crop.width) == 200)
        }
    }

    @Test
    func mappingAFullImageBoxIsIdentityAndALowerTileMovesUpFromTheBottom() {
        let box = CGRect(x: 0.2, y: 0.3, width: 0.1, height: 0.05)
        let same = VisionTextTiles.map(
            box: box,
            crop: CGRect(x: 0, y: 0, width: 100, height: 200),
            imageWidth: 100,
            imageHeight: 200
        )
        #expect(abs(same.minX - 0.2) < 0.0001)
        #expect(abs(same.minY - 0.3) < 0.0001)

        let lower = VisionTextTiles.map(
            box: CGRect(x: 0, y: 0, width: 1, height: 1),
            crop: CGRect(x: 0, y: 100, width: 100, height: 50),
            imageWidth: 100,
            imageHeight: 200
        )
        #expect(abs(lower.minY - 0.25) < 0.0001)
        #expect(abs(lower.height - 0.25) < 0.0001)
    }

    @Test
    func anOverlapCenterIsKeptByOnlyOneTile() {
        let width = 200
        let height = 1000
        let tiles = VisionTextTiles.tiles(width: width, height: height)
        #expect(tiles.count >= 2)
        let first = tiles[0]
        let second = tiles[1]
        let overlap = first.crop.intersection(second.crop)
        #expect(overlap.height > 1)
        let centerFromTop = overlap.midY
        let center = CGPoint(x: 0.5, y: (CGFloat(height) - centerFromTop) / CGFloat(height))
        let owners = tiles.filter { $0.contains(center: center) }
        #expect(owners.count == 1)
    }

    @Test
    @MainActor
    func liveTallStripKeepsEveryLineOnce() throws {
        let words = tallStripWords(count: 36)
        let image = try tallStrip(words: words)
        let before = try untiledWords(in: image)
        let encoded = try pngData(image).base64EncodedString()
        let response = VisionProvider().handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(encoded)","recognition_languages":["en-US"]}"#
        )
        guard response.ok else {
            #expect(response.errorJson?.contains("vision_error") == true)
            return
        }
        let payload = response.payloadJson
        let lines = candidateStrings(in: payload)
        let after = uniqueWords(in: lines.joined(separator: " "))
        print("TALL_STRIP words_before=\(before.count) words_after=\(after.count) expected=\(words.count)")
        let missing = words.filter { after.contains($0) == false }
        #expect(missing.isEmpty, "missing \(missing) before=\(before.count) after=\(after.count)")
        for word in words {
            let hits = lines.filter { uniqueWords(in: $0).contains(word) }.count
            #expect(hits == 1, "\(word) appeared \(hits) times")
        }
    }

    private func candidateStrings(in payload: String) -> [String] {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]]
        else {
            return []
        }
        return results.flatMap { result in
            let candidates = result["candidates"] as? [[String: Any]] ?? []
            return candidates.compactMap { $0["string"] as? String }
        }
    }

    private func untiledWords(in image: CGImage) throws -> Set<String> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        return uniqueWords(in: text)
    }

    private func uniqueWords(in text: String) -> Set<String> {
        let tokens = text.uppercased().split { character in
            character.isLetter == false && character.isNumber == false
        }
        return Set(tokens.filter { $0.count >= 4 }.map(String.init))
    }

    /// Letters Vision does not trade for digits. Avoids O/0, I/1, S/5, B/8, Z/2.
    private func tallStripWords(count: Int) -> [String] {
        let alphabet = Array("ACDEFGHKMNPRTUVWXY")
        return (0 ..< count).map { index in
            let first = alphabet[index / alphabet.count]
            let second = alphabet[index % alphabet.count]
            return "TX\(first)\(second)"
        }
    }

    private func tallStrip(words: [String]) throws -> CGImage {
        let width = 420
        let height = 3780
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
            throw VisionProviderError.visionError("Failed to create a tall strip")
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = NSFont.systemFont(ofSize: 22, weight: .regular)
        let step = (height - 48) / words.count
        for (index, word) in words.enumerated() {
            let baseline = 24 + index * step
            draw(word, at: CGPoint(x: 24, y: baseline), font: font, in: context)
        }
        return try #require(context.makeImage())
    }

    private func draw(_ text: String, at point: CGPoint, font: NSFont, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw VisionProviderError.visionError("Failed to encode a tall strip")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VisionProviderError.visionError("Failed to encode a tall strip")
        }
        return data as Data
    }
}

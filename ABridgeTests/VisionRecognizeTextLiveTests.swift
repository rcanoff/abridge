@testable import ABridge
import AppKit
import CoreGraphics
import CoreText
import Darwin
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@Suite("VisionRecognizeTextLive")
struct VisionRecognizeTextLiveTests {
    private struct RecognizedLine {
        var text: String
        var left: Double
        var top: Double
        var bottom: Double
        var height: Double
    }

    private let expected = """
    ALPHA BRAVO
    CHARLIE DELTA
    ECHO FOXTROT
    GOLF HOTEL
    """

    @Test
    @MainActor
    func recognizeTextAssemblesTwoColumnsFromAGeneratedImage() throws {
        let image = try twoColumnImageData()
        let encoded = image.base64EncodedString()
        let provider = VisionProvider()
        let response = provider.handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )
        #expect(response.ok == true, "Expected success, got: \(response.errorJson ?? "nil")")
        let payload = response.payloadJson
        let assembled = try normalize(assembledText(from: payload))
        #expect(assembled == expected, "Vision read:\n\(assembled)")

        let after = try JSONSerialization.data(withJSONObject: ["text": assembled])
        let documents = provider.handle(
            operation: "recognize_documents",
            payloadJson: #"{"image_data":"\#(encoded)"}"#
        )
        #expect(documents.ok == true, "Expected documents success, got: \(documents.errorJson ?? "nil")")
        for word in ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT", "GOLF", "HOTEL"] {
            #expect(documents.payloadJson.contains(word), "Missing \(word) in document JSON")
        }
        print("RECEIPT_SIZE text_before=\(payload.utf8.count) text_after=\(after.count)")
        print("RECEIPT_SIZE documents_before=\(documents.payloadJson.utf8.count)")
        if let directory = ProcessInfo.processInfo.environment["ABRIDGE_VISION_RECEIPT_DIR"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try payload.write(to: folder.appending(path: "recognize-text.json"), atomically: true, encoding: .utf8)
            try documents.payloadJson.write(
                to: folder.appending(path: "recognize-documents.json"),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    private func twoColumnImageData() throws -> Data {
        let width = 1100
        let height = 520
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
            throw VisionProviderError.visionError("Failed to create two-column image")
        }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = NSFont.systemFont(ofSize: 56, weight: .bold)
        let rows = [
            (left: "ALPHA", right: "BRAVO", y: 430),
            (left: "CHARLIE", right: "DELTA", y: 320),
            (left: "ECHO", right: "FOXTROT", y: 210),
            (left: "GOLF", right: "HOTEL", y: 100),
        ]
        for row in rows {
            draw(row.left, at: CGPoint(x: 48, y: row.y), font: font, in: context)
            draw(row.right, at: CGPoint(x: 620, y: row.y), font: font, in: context)
        }
        guard let cgImage = context.makeImage() else {
            throw VisionProviderError.visionError("Failed to render two-column image")
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw VisionProviderError.visionError("Failed to create two-column PNG")
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VisionProviderError.visionError("Failed to finalize two-column PNG")
        }
        return data as Data
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

    private func assembledText(from payload: String) throws -> String {
        let data = try #require(payload.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let results = try #require(object["results"] as? [[String: Any]])
        var lines: [RecognizedLine] = []
        lines.reserveCapacity(results.count)
        for observation in results {
            guard let candidates = observation["candidates"] as? [[String: Any]],
                  let raw = candidates.first?["string"] as? String
            else { continue }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  let box = observation["bounding_box"] as? [String: Any],
                  let origin = box["origin"] as? [String: Any],
                  let size = box["size"] as? [String: Any],
                  let originX = jsonNumber(origin["x"]),
                  let originY = jsonNumber(origin["y"])
            else { continue }
            let height = jsonNumber(size["height"]) ?? 0
            lines.append(
                RecognizedLine(text: text, left: originX, top: originY + height, bottom: originY, height: height)
            )
        }
        return assemble(lines)
    }

    private func assemble(_ lines: [RecognizedLine]) -> String {
        let sorted = lines.sorted { lhs, rhs in
            if lhs.top != rhs.top {
                return lhs.top > rhs.top
            }
            return lhs.left < rhs.left
        }
        var rows: [[RecognizedLine]] = []
        for line in sorted {
            if let last = rows.last, sameRow(last, line) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { row in
            row.sorted { $0.left < $1.left }.map(\.text).joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    private func sameRow(_ row: [RecognizedLine], _ line: RecognizedLine) -> Bool {
        let top = row.map(\.top).max() ?? line.top
        let bottom = row.map(\.bottom).min() ?? line.bottom
        let overlap = min(top, line.top) - max(bottom, line.bottom)
        let minHeight = min(row.map(\.height).min() ?? line.height, line.height)
        if minHeight <= .leastNonzeroMagnitude {
            return abs((top + bottom) / 2 - (line.top + line.bottom) / 2) <= 0.02
        }
        return overlap >= minHeight * 0.5
    }

    private func normalize(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    private func jsonNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number.doubleValue
    }
}

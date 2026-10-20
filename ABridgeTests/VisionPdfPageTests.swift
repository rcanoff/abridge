@testable import ABridge
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Testing

@Suite("Vision PDF pages")
struct VisionPdfPageTests {
    @Test
    @MainActor
    func pageTwoIsTheSecondPageOnEveryVisionTool() throws {
        let pdf = try VisionPdfSamples.twoPageDocument()
        let encoded = pdf.base64EncodedString()
        let operations = ["recognize_text", "recognize_documents", "detect_barcodes", "detect_face_landmarks"]

        for operation in operations {
            let store = MockVisionStore()
            let response = VisionProvider(store: store).handle(
                operation: operation,
                payloadJson: #"{"image_data":"\#(encoded)","page":2}"#
            )
            #expect(response.ok == true, "\(operation) \(response.errorJson ?? "")")
            let object = try jsonObject(response.payloadJson)
            #expect(object["page"] as? Int == 2)
            #expect(object["page_count"] as? Int == 2)
            let size = try pixelSize(#require(store.lastPreparedImageData))
            #expect(size.width > size.height, "\(operation) should render the wide second page")
            #expect(size.width == 1200)
            #expect(size.height == 400)
        }
    }

    @Test
    @MainActor
    func omittedPageRendersTheFirstPage() throws {
        let pdf = try VisionPdfSamples.twoPageDocument()
        let store = MockVisionStore()
        let response = VisionProvider(store: store).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(pdf.base64EncodedString())"}"#
        )
        #expect(response.ok == true)
        let object = try jsonObject(response.payloadJson)
        #expect(object["page"] as? Int == 1)
        #expect(object["page_count"] as? Int == 2)
        let size = try pixelSize(#require(store.lastPreparedImageData))
        #expect(size.height > size.width)
        #expect(size.width == 400)
        #expect(size.height == 800)

        let explicit = VisionProvider(store: store).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(pdf.base64EncodedString())","page":1}"#
        )
        #expect(explicit.ok == true, "explicit page 1 \(explicit.errorJson ?? "")")
        #expect(try jsonObject(explicit.payloadJson)["page"] as? Int == 1)
    }

    @Test
    @MainActor
    func pagePastTheEndNamesThePageCount() throws {
        let pdf = try VisionPdfSamples.twoPageDocument()
        let store = MockVisionStore()
        let response = VisionProvider(store: store).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(pdf.base64EncodedString())","page":3}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("page_out_of_range") == true)
        #expect(response.errorJson?.contains("2") == true)
        #expect(store.lastPreparedImageData == nil)
    }

    @Test
    @MainActor
    func pageGreaterThanOneOnAnImageIsRejected() throws {
        let image = try VisionTestFixtures.sampleTextImageData()
        let response = VisionProvider(store: MockVisionStore()).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(image.base64EncodedString())","page":2}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("single image") == true)
    }

    @Test
    @MainActor
    func anImageResultOmitsPageFields() throws {
        let image = try VisionTestFixtures.sampleTextImageData()
        let store = MockVisionStore()
        store.observations = try VisionTestFixtures.sampleRecognizedTextObservations()
        let response = VisionProvider(store: store).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(image.base64EncodedString())"}"#
        )
        #expect(response.ok == true)
        let object = try jsonObject(response.payloadJson)
        #expect(object["page"] == nil)
        #expect(object["page_count"] == nil)
        #expect(store.lastPreparedImageData == image)
    }

    @Test
    @MainActor
    func aPdfIsDetectedByContentNotExtension() throws {
        let pdf = try VisionPdfSamples.twoPageDocument()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("abridge-vision-\(UUID().uuidString).png")
        try pdf.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = MockVisionStore()
        let response = VisionProvider(store: store).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_path":"\#(url.path)","page":2}"#
        )
        #expect(response.ok == true, "image_path PDF \(response.errorJson ?? "")")
        let object = try jsonObject(response.payloadJson)
        #expect(object["page"] as? Int == 2)
        #expect(object["page_count"] as? Int == 2)

        let image = try VisionTestFixtures.sampleTextImageData()
        let renamed = FileManager.default.temporaryDirectory
            .appendingPathComponent("abridge-vision-\(UUID().uuidString).pdf")
        try image.write(to: renamed)
        defer { try? FileManager.default.removeItem(at: renamed) }
        let imageResponse = VisionProvider(store: MockVisionStore()).handle(
            operation: "detect_barcodes",
            payloadJson: #"{"image_path":"\#(renamed.path)","page":2}"#
        )
        #expect(imageResponse.ok == false)
        #expect(imageResponse.errorJson?.contains("single image") == true)
    }

    @Test
    @MainActor
    func anEncryptedPdfIsAnError() throws {
        let encrypted = try VisionPdfSamples.encryptedDocument()
        let response = VisionProvider(store: MockVisionStore()).handle(
            operation: "recognize_documents",
            payloadJson: #"{"image_data":"\#(encrypted.base64EncodedString())"}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("encrypted") == true)
    }

    @Test
    @MainActor
    func anUnreadablePdfIsAnError() {
        let garbage = Data("%PDF-1.7\nnot a pdf".utf8).base64EncodedString()
        let response = VisionProvider(store: MockVisionStore()).handle(
            operation: "detect_face_landmarks",
            payloadJson: #"{"image_data":"\#(garbage)","page":1}"#
        )
        #expect(response.ok == false)
        #expect(
            response.errorJson?.contains("could not be read") == true,
            "\(response.errorJson ?? "")"
        )
    }

    @Test
    @MainActor
    func pageBelowOneIsRejected() throws {
        let image = try VisionTestFixtures.sampleTextImageData()
        let response = VisionProvider(store: MockVisionStore()).handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(image.base64EncodedString())","page":0}"#
        )
        #expect(response.ok == false)
        #expect(response.errorJson?.contains("invalid_arguments") == true)
        #expect(response.errorJson?.contains("page") == true)
    }

    @Test
    func bitmapSizeIsTwiceThePointSizeUntilThePixelCap() {
        let page = VisionPdf.bitmapSize(for: CGSize(width: 200, height: 400))
        #expect(page?.width == 400)
        #expect(page?.height == 800)

        let huge = VisionPdf.bitmapSize(for: CGSize(width: 10000, height: 10000))
        let pixels = (huge?.width ?? 0) * (huge?.height ?? 0)
        #expect(pixels > 0)
        #expect(pixels <= VisionPdf.maxBitmapPixels)
        #expect((huge?.width ?? 0) < 20000)
    }

    @Test
    func renderedPageFillsTheBitmapAtTwicePointSize() throws {
        let pdf = try VisionPdfSamples.markedPage(size: CGSize(width: 180, height: 360))
        let prepared = try VisionPdf.prepare(data: pdf, page: 1)
        let image = try cgImage(prepared.imageData)
        #expect(image.width == 360)
        #expect(image.height == 720)
        #expect(darkSamples(in: image, fromTop: 0 ..< 0.08) > 0, "top bar was not scaled into the bitmap")
        #expect(darkSamples(in: image, fromTop: 0.92 ..< 1) > 0, "bottom bar was not scaled into the bitmap")
    }

    @Test
    @MainActor
    func liveRecognizeTextReadsPageTwoWhenVisionIsAvailable() throws {
        let pdf = try VisionPdfSamples.twoPageDocument()
        let response = VisionProvider().handle(
            operation: "recognize_text",
            payloadJson: #"{"image_data":"\#(pdf.base64EncodedString())","page":2,"recognition_languages":["en-US"]}"#
        )
        let object = try jsonObject(response.payloadJson)
        guard response.ok else {
            #expect(response.errorJson?.contains("vision_error") == true)
            return
        }
        #expect(object["page"] as? Int == 2)
        #expect(object["page_count"] as? Int == 2)
        let text = recognizedText(in: object)
        if text.isEmpty == false {
            #expect(text.contains("PAGETWO"))
            #expect(text.contains("PAGEONE") == false)
        }
    }

    private func jsonObject(_ payload: String) throws -> [String: Any] {
        let data = try #require(payload.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func pixelSize(_ data: Data) throws -> (width: Int, height: Int) {
        let image = try cgImage(data)
        return (image.width, image.height)
    }

    private func cgImage(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// Dark samples in a fraction of the bitmap measured from the top. CGImage rows are top-left origin.
    private func darkSamples(in image: CGImage, fromTop: Range<CGFloat>) -> Int {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let start = max(0, Int((fromTop.lowerBound * CGFloat(height)).rounded(.down)))
        let end = min(height, Int((fromTop.upperBound * CGFloat(height)).rounded(.up)))
        var dark = 0
        for yFromTop in start ..< end {
            let row = height - 1 - yFromTop
            for column in stride(from: 0, to: width, by: 3) {
                let offset = (row * width + column) * 4
                if pixels[offset] < 128 {
                    dark += 1
                }
            }
        }
        return dark
    }

    private func recognizedText(in object: [String: Any]) -> String {
        let results = object["results"] as? [[String: Any]] ?? []
        return results.flatMap { result in
            let candidates = result["candidates"] as? [[String: Any]] ?? []
            return candidates.compactMap { $0["string"] as? String }
        }.joined(separator: " ")
    }
}

enum VisionPdfSamples {
    static func twoPageDocument() throws -> Data {
        let tall = try singlePage(size: CGSize(width: 200, height: 400), text: "PAGEONE")
        let wide = try singlePage(size: CGSize(width: 600, height: 200), text: "PAGETWO")
        let document = try #require(PDFDocument(data: tall))
        let second = try #require(PDFDocument(data: wide))
        let page = try #require(second.page(at: 0))
        document.insert(page, at: 1)
        return try #require(document.dataRepresentation())
    }

    static func markedPage(size: CGSize) throws -> Data {
        let data = NSMutableData()
        var media = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil)
        else {
            throw VisionProviderError.visionError("Failed to create a sample PDF")
        }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(media)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: size.height - 20, width: size.width, height: 20))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: 20))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    static func encryptedDocument() throws -> Data {
        let document = try #require(try PDFDocument(data: singlePage(
            size: CGSize(width: 200, height: 200),
            text: "SECRET"
        )))
        return try #require(document.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: "secret",
            PDFDocumentWriteOption.ownerPasswordOption: "secret",
        ]))
    }

    private static func singlePage(size: CGSize, text: String) throws -> Data {
        let data = NSMutableData()
        var media = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil)
        else {
            throw VisionProviderError.visionError("Failed to create a sample PDF")
        }
        context.beginPDFPage(nil)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(media)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(gray: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: 24, y: 24)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}

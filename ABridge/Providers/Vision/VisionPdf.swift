import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct VisionPdfInfo: Equatable, Sendable {
    let page: Int
    let pageCount: Int
}

struct VisionPreparedImage: Equatable, Sendable {
    /// PNG of the selected PDF page, or the original bytes when the input is an image.
    let imageData: Data
    let pdf: VisionPdfInfo?
}

/// Rasterizes one PDF page for Vision. Recognition is by a `%PDF-` header, not the file extension.
enum VisionPdf {
    /// Long edge of the rendered page. Inside the 2048...4096 range used for OCR.
    static let longEdgePixels = 3072

    /// Caps the bitmap at a square of `longEdgePixels`, about 36 MiB of RGBA.
    static let maxBitmapPixels = longEdgePixels * longEdgePixels

    static func prepare(data: Data, page: Int) throws -> VisionPreparedImage {
        guard page >= 1 else {
            throw VisionProviderError.invalidArguments("page must be an integer greater than or equal to 1")
        }
        if isPDF(data) {
            let rendered = try render(data: data, page: page)
            return VisionPreparedImage(
                imageData: rendered.imageData,
                pdf: VisionPdfInfo(page: page, pageCount: rendered.pageCount)
            )
        }
        if page > 1 {
            if decodesAsImage(data) {
                throw VisionProviderError.invalidArguments(
                    "page must be 1 for an image; this file is a single image"
                )
            }
            throw VisionProviderError.invalidArguments("image_data could not be decoded as an image")
        }
        return VisionPreparedImage(imageData: data, pdf: nil)
    }

    private static let header = Data("%PDF-".utf8)

    /// ISO 32000 places the header in the first 1024 bytes.
    private static func isPDF(_ data: Data) -> Bool {
        data.prefix(1024).range(of: header) != nil
    }

    private static func decodesAsImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    private static func render(data: Data, page: Int) throws -> (imageData: Data, pageCount: Int) {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider)
        else {
            throw VisionProviderError.invalidArguments("PDF could not be read")
        }
        if !document.isUnlocked {
            throw VisionProviderError.invalidArguments("PDF is encrypted and cannot be read")
        }
        let pageCount = document.numberOfPages
        guard pageCount >= 1 else {
            throw VisionProviderError.invalidArguments("PDF could not be read")
        }
        guard page <= pageCount else {
            throw VisionProviderError.pageOutOfRange(
                "page \(page) does not exist; the PDF has \(pageCount) page(s)"
            )
        }
        guard let pdfPage = document.page(at: page) else {
            throw VisionProviderError.invalidArguments("PDF page could not be rendered")
        }
        let image = try rasterize(pdfPage)
        return try (pngData(from: image), pageCount)
    }

    private static func rasterize(_ page: CGPDFPage) throws -> CGImage {
        let box = displayBox(for: page)
        let displayed = displayedSize(of: page, box: box)
        guard let pixels = pixelSize(for: displayed) else {
            throw VisionProviderError.invalidArguments("PDF page could not be rendered")
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixels.width,
            height: pixels.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw VisionProviderError.invalidArguments("PDF page could not be rendered")
        }
        context.interpolationQuality = .high
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        let destination = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
        let transform = page.getDrawingTransform(box, rect: destination, rotate: 0, preserveAspectRatio: true)
        context.concatenate(transform)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else {
            throw VisionProviderError.invalidArguments("PDF page could not be rendered")
        }
        return image
    }

    private static func displayBox(for page: CGPDFPage) -> CGPDFBox {
        let crop = page.getBoxRect(.cropBox)
        if crop.width > 1, crop.height > 1 {
            return .cropBox
        }
        return .mediaBox
    }

    private static func displayedSize(of page: CGPDFPage, box: CGPDFBox) -> CGSize {
        let rect = page.getBoxRect(box)
        let angle = ((page.rotationAngle % 360) + 360) % 360
        if angle == 90 || angle == 270 {
            return CGSize(width: rect.height, height: rect.width)
        }
        return rect.size
    }

    private static func pixelSize(for displayed: CGSize) -> (width: Int, height: Int)? {
        guard displayed.width > 0, displayed.height > 0 else { return nil }
        let scale = CGFloat(longEdgePixels) / max(displayed.width, displayed.height)
        var width = max(1, Int((displayed.width * scale).rounded()))
        var height = max(1, Int((displayed.height * scale).rounded()))
        while true {
            let product = width.multipliedReportingOverflow(by: height)
            if !product.overflow, product.partialValue <= maxBitmapPixels {
                break
            }
            if width == 1, height == 1 {
                break
            }
            width = max(1, width / 2)
            height = max(1, height / 2)
        }
        return (width, height)
    }

    private static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw VisionProviderError.invalidArguments("PDF page could not be rendered")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw VisionProviderError.invalidArguments("PDF page could not be rendered")
        }
        return data as Data
    }
}

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
    /// Points to pixels. About 2× was the best or near-best scale on real scans.
    static let renderScale: CGFloat = 2

    /// RGBA memory bound, about 40 million pixels (roughly 160 MiB).
    static let maxBitmapPixels = 40_000_000

    struct BitmapSize: Equatable {
        let width: Int
        let height: Int
        let scale: CGFloat
    }

    /// Pixel size of a page with `displayed` point size, at `renderScale` until the pixel cap.
    static func bitmapSize(for displayed: CGSize) -> BitmapSize? {
        guard displayed.width > 0, displayed.height > 0,
              displayed.width.isFinite, displayed.height.isFinite
        else {
            return nil
        }
        let area = displayed.width * displayed.height
        var scale = renderScale
        if area * scale * scale > CGFloat(maxBitmapPixels) {
            scale = (CGFloat(maxBitmapPixels) / area).squareRoot()
        }
        var width = max(1, Int((displayed.width * scale).rounded(.down)))
        var height = max(1, Int((displayed.height * scale).rounded(.down)))
        var guardCount = 0
        while width * height > maxBitmapPixels, width > 1, height > 1, guardCount < 8 {
            scale *= 0.99
            width = max(1, Int((displayed.width * scale).rounded(.down)))
            height = max(1, Int((displayed.height * scale).rounded(.down)))
            guardCount += 1
        }
        let fitted = min(CGFloat(width) / displayed.width, CGFloat(height) / displayed.height)
        return BitmapSize(width: width, height: height, scale: fitted)
    }

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

    /// `getDrawingTransform` only scales down, so a page smaller than the destination is drawn at
    /// 1× inside a white canvas. Scale explicitly instead.
    private static func rasterize(_ page: CGPDFPage) throws -> CGImage {
        let box = displayBox(for: page)
        let pageRect = page.getBoxRect(box)
        let displayed = displayedSize(of: page, box: box)
        guard let pixels = bitmapSize(for: displayed) else {
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
        context.clip(to: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        context.concatenate(drawingTransform(pageRect: pageRect, rotation: page.rotationAngle, scale: pixels.scale))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else {
            throw VisionProviderError.invalidArguments("PDF page could not be rendered")
        }
        return image
    }

    /// Maps the page box into the bitmap. Each new step is applied after the ones above it,
    /// so the origin shift happens first and the rotation shift happens last.
    private static func drawingTransform(pageRect: CGRect, rotation: Int32, scale: CGFloat) -> CGAffineTransform {
        let angle = ((Int(rotation) % 360) + 360) % 360
        var transform = CGAffineTransform(translationX: -pageRect.origin.x, y: -pageRect.origin.y)
        transform = transform.scaledBy(x: scale, y: scale)
        switch angle {
        case 90:
            transform = transform.rotated(by: -.pi / 2)
            transform = transform.translatedBy(x: 0, y: pageRect.width * scale)
        case 180:
            transform = transform.rotated(by: .pi)
            transform = transform.translatedBy(x: pageRect.width * scale, y: pageRect.height * scale)
        case 270:
            transform = transform.rotated(by: .pi / 2)
            transform = transform.translatedBy(x: pageRect.height * scale, y: 0)
        default:
            break
        }
        return transform
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

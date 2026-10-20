import CoreGraphics
import Foundation

/// Splits a tall image into overlapping tiles for `vision_recognize_text`.
///
/// A tile is kept only when the observation center falls in that tile's core. Cores partition
/// the page, meeting at the midpoint of each overlap, so a line in the overlap is kept once.
/// A wide image stays one tile: splitting along the width cuts every text line.
enum VisionTextTiles {
    /// Tile when the oriented height is more than this multiple of the width.
    static let aspectLimit: CGFloat = 1.5

    /// Each tile's long side is at most this multiple of the image's short side.
    static let tileLongMultiple: CGFloat = 1.25

    /// Overlap as a fraction of the tile length. About 15% keeps a line from being cut at the core edge.
    static let overlapFraction: CGFloat = 0.15

    struct Tile: Equatable {
        /// Crop in CGImage pixels, origin at the top left.
        let crop: CGRect
        /// Core along the long axis in whole-image Vision coordinates (origin at the bottom left).
        let coreMin: CGFloat
        let coreMax: CGFloat
        let vertical: Bool

        func contains(center: CGPoint) -> Bool {
            let axis = vertical ? center.y : center.x
            return axis >= coreMin && axis < coreMax
        }
    }

    /// `width` and `height` are pixels after orientation has been drawn out.
    static func tiles(width: Int, height: Int) -> [Tile] {
        guard width > 0, height > 0 else { return [] }
        let vertical = height >= width
        let shortSide = min(width, height)
        let longSide = max(width, height)
        let full = Tile(
            crop: CGRect(x: 0, y: 0, width: width, height: height),
            coreMin: -.infinity,
            coreMax: .infinity,
            vertical: vertical
        )
        // Wide and nearly square images stay whole. A side-by-side split cuts every line.
        guard CGFloat(height) > CGFloat(width) * aspectLimit else {
            return [full]
        }

        let tileLength = min(longSide, max(1, Int((CGFloat(shortSide) * tileLongMultiple).rounded(.down))))
        guard tileLength < longSide else { return [full] }
        var overlap = Int((CGFloat(tileLength) * overlapFraction).rounded())
        if overlap <= 0 {
            overlap = 1
        }
        if overlap >= tileLength {
            overlap = tileLength - 1
        }
        let step = max(1, tileLength - overlap)
        let starts = tileStarts(longSide: longSide, tileLength: tileLength, step: step)
        let plan = TilePlan(
            width: width,
            height: height,
            vertical: vertical,
            tileLength: tileLength,
            longSide: longSide
        )
        return tiles(starts: starts, plan: plan)
    }

    private struct TilePlan {
        let width: Int
        let height: Int
        let vertical: Bool
        let tileLength: Int
        let longSide: Int
    }

    private struct Span {
        let start: Int
        let low: Int
        let high: Int
    }

    private static func tileStarts(longSide: Int, tileLength: Int, step: Int) -> [Int] {
        var starts = [0]
        var cursor = step
        while cursor + tileLength < longSide {
            starts.append(cursor)
            cursor += step
        }
        let last = longSide - tileLength
        if let previous = starts.last, last > previous {
            starts.append(last)
        }
        return starts
    }

    private static func tiles(starts: [Int], plan: TilePlan) -> [Tile] {
        let spans = starts.map { start in
            if plan.vertical {
                Span(start: start, low: plan.height - start - plan.tileLength, high: plan.height - start)
            } else {
                Span(start: start, low: start, high: start + plan.tileLength)
            }
        }.sorted { $0.low < $1.low }

        return spans.enumerated().map { index, span in
            let coreMin = index == 0
                ? -CGFloat.infinity
                : (CGFloat(spans[index - 1].high) + CGFloat(span.low)) / 2 / CGFloat(plan.longSide)
            let coreMax = index == spans.count - 1
                ? CGFloat.infinity
                : (CGFloat(span.high) + CGFloat(spans[index + 1].low)) / 2 / CGFloat(plan.longSide)
            let crop = plan.vertical
                ? CGRect(x: 0, y: span.start, width: plan.width, height: plan.tileLength)
                : CGRect(x: span.start, y: 0, width: plan.tileLength, height: plan.height)
            return Tile(crop: crop, coreMin: coreMin, coreMax: coreMax, vertical: plan.vertical)
        }
    }

    /// Vision box on a tile, mapped to whole-image normalized coordinates (origin at the bottom left).
    static func map(box: CGRect, crop: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        let imageW = CGFloat(imageWidth)
        let imageH = CGFloat(imageHeight)
        let width = box.width * crop.width / imageW
        let height = box.height * crop.height / imageH
        let originX = (crop.minX + box.origin.x * crop.width) / imageW
        let originY = (imageH - crop.maxY + box.origin.y * crop.height) / imageH
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    static func map(point: CGPoint, crop: CGRect, imageWidth: Int, imageHeight: Int) -> CGPoint {
        let imageW = CGFloat(imageWidth)
        let imageH = CGFloat(imageHeight)
        return CGPoint(
            x: (crop.minX + point.x * crop.width) / imageW,
            y: (imageH - crop.maxY + point.y * crop.height) / imageH
        )
    }

    /// Tile rectangle in whole-image Vision coordinates, given the image the crop was taken from.
    static func visionRect(crop: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect {
        let imageW = CGFloat(imageWidth)
        let imageH = CGFloat(imageHeight)
        return CGRect(
            x: crop.minX / imageW,
            y: (imageH - crop.maxY) / imageH,
            width: crop.width / imageW,
            height: crop.height / imageH
        )
    }

    /// `interest` is a whole-image Vision rectangle. The result is that region inside the tile, or nil
    /// when the tile misses it.
    static func localRegion(_ interest: CGRect, crop: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect? {
        let tile = visionRect(crop: crop, imageWidth: imageWidth, imageHeight: imageHeight)
        let overlap = tile.intersection(interest)
        guard overlap.width > 0.001, overlap.height > 0.001 else { return nil }
        let local = CGRect(
            x: (overlap.minX - tile.minX) / tile.width,
            y: (overlap.minY - tile.minY) / tile.height,
            width: overlap.width / tile.width,
            height: overlap.height / tile.height
        )
        return local.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

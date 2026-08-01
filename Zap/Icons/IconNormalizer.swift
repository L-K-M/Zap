import CoreGraphics

/// Makes icons of wildly different shapes sit in one row without looking ragged
/// (`UNJAILED.md §8.3`).
///
/// A row built for squares mistreats free-form art three ways, and this fixes all
/// three before the bitmap is ever cached:
///
/// 1. **Trim.** Source artwork often carries transparent margin, which would leave
///    the icon floating small inside its cell.
/// 2. **Scale by ink, not by bounding box.** `.aspectRatio(.fit)` in a square frame
///    letterboxes a wide icon, so it renders at half the visual weight of its
///    neighbours. Matching the *ink area* instead means a circle and a square read
///    as the same size — which is what Apple's own icon grid does.
/// 3. **Shadow.** Free-form art on a translucent blurred panel loses its edges. The
///    system's own icons get a silhouette for free from the grey plate; without the
///    plate, a soft drop shadow puts it back.
///
/// All of it is baked into the cached bitmap by `IconResolver`, never applied per
/// frame — a SwiftUI `.shadow` on 40 icons per frame would show up on the hot path.
enum IconNormalizer {

    /// Ink coverage a normalised icon aims for, as a fraction of the nominal icon
    /// frame's area.
    ///
    /// 0.95 is the measured coverage of a Tahoe superellipse over its own bounding
    /// box (`IconShapeClassifier`) — i.e. the weight of an ordinary system icon. A
    /// solid square therefore shrinks a touch, a circle grows ~10%, and a thin
    /// free-form shape grows until the bleed stops it.
    static let referenceInkFraction = 0.95

    /// Grid the trim rectangle is measured on. Finer than the classifier's, because
    /// this one becomes a crop: at 256 over a 1024px master each cell is 4px, so
    /// the trim can't visibly clip the artwork.
    static let trimResolution = 256

    /// Shadow geometry, as fractions of the canvas.
    private static let shadowBlurFraction = 0.045
    private static let shadowAlpha = 0.38

    // MARK: Pure layout

    /// How the trimmed artwork is scaled to carry a standard amount of ink.
    struct Layout: Equatable {
        /// Multiplier applied to the trimmed source.
        var scale: Double
        /// Whether the bleed stopped the artwork short of equal ink. A very sparse
        /// shape (a thin cross, a hairline glyph) would otherwise grow without
        /// bound chasing the reference.
        var wasClamped: Bool
    }

    /// The equal-ink scale for one icon — pure arithmetic, so the rule that a circle
    /// and a square land at the same visual weight is directly testable.
    ///
    /// - Parameters:
    ///   - inkFraction: inked area over the trimmed bounding box's area, 0...1.
    ///   - trimmedWidth/trimmedHeight: the trimmed artwork's size, any unit.
    ///   - targetExtent: the nominal icon frame, same unit.
    ///   - bleed: headroom on each side, as a fraction of `targetExtent`.
    static func layout(inkFraction: Double, trimmedWidth: Double, trimmedHeight: Double,
                       targetExtent: Double, bleed: Double) -> Layout {
        guard trimmedWidth > 0, trimmedHeight > 0, targetExtent > 0,
              inkFraction > 0, inkFraction.isFinite else {
            return Layout(scale: 1, wasClamped: false)
        }

        let canvas = canvasExtent(targetExtent: targetExtent, bleed: bleed)
        let targetInk = referenceInkFraction * targetExtent * targetExtent
        let sourceInk = inkFraction * trimmedWidth * trimmedHeight
        let equalInkScale = (targetInk / sourceInk).squareRoot()

        // Never outgrow the canvas the bleed bought: the art has to stay inside its
        // cell, or it meets the row's clip.
        let maximumScale = canvas / max(trimmedWidth, trimmedHeight)
        guard equalInkScale > maximumScale else {
            return Layout(scale: equalInkScale, wasClamped: false)
        }
        return Layout(scale: maximumScale, wasClamped: true)
    }

    /// Extent of the canvas an icon is rendered into, nominal frame plus bleed on
    /// each side. Mirrors `IconRowMetrics.imageExtent(iconSize:bleed:)`.
    static func canvasExtent(targetExtent: Double, bleed: Double) -> Double {
        targetExtent * (1 + 2 * clampedBleed(bleed))
    }

    static func clampedBleed(_ bleed: Double) -> Double {
        guard bleed.isFinite else { return 0 }
        return min(max(bleed, 0), Double(IconRowMetrics.maximumBleed))
    }

    // MARK: Rendering

    /// Trims, scales and (optionally) shadows `image` into a square canvas of
    /// `targetExtent * (1 + 2 * bleed)` pixels. Returns the input unchanged if it
    /// carries no ink or can't be rasterised.
    static func normalize(_ image: CGImage, targetExtent: Int, bleed: Double,
                          trim: Bool, shadow: Bool) -> CGImage {
        guard targetExtent > 0 else { return image }

        let canvasSide = Int(canvasExtent(targetExtent: Double(targetExtent), bleed: bleed).rounded())
        guard canvasSide > 0 else { return image }

        guard let mask = AlphaMask(image: image, longestEdge: trimResolution) else { return image }
        let threshold = IconShapeClassifier.inkThreshold
        let inked = mask.inkCount(threshold: threshold)
        guard inked > 0, let bounds = mask.inkBounds(threshold: threshold) else { return image }

        // Mask row 0 is the image's top row, matching `CGImage.cropping(to:)`'s
        // upper-left origin — the two conventions agree, so the crop needs no flip.
        let cellWidth = Double(image.width) / Double(mask.width)
        let cellHeight = Double(image.height) / Double(mask.height)

        let source: CGImage
        let inkFraction: Double
        if trim {
            let cropRect = CGRect(x: Double(bounds.minColumn) * cellWidth,
                                  y: Double(bounds.minRow) * cellHeight,
                                  width: Double(bounds.columnCount) * cellWidth,
                                  height: Double(bounds.rowCount) * cellHeight).integral
            source = image.cropping(to: cropRect) ?? image
            inkFraction = Double(inked) / Double(bounds.columnCount * bounds.rowCount)
        } else {
            source = image
            inkFraction = Double(inked) / Double(mask.width * mask.height)
        }

        let scaling = layout(inkFraction: inkFraction,
                             trimmedWidth: Double(source.width),
                             trimmedHeight: Double(source.height),
                             targetExtent: Double(targetExtent),
                             bleed: bleed)

        return render(source, scaling: scaling, canvasSide: canvasSide, shadow: shadow) ?? image
    }

    private static func render(_ source: CGImage, scaling: Layout,
                               canvasSide: Int, shadow: Bool) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: canvasSide, height: canvasSide,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let width = Double(source.width) * scaling.scale
        let height = Double(source.height) * scaling.scale
        let canvas = Double(canvasSide)
        let drawRect = CGRect(x: (canvas - width) / 2, y: (canvas - height) / 2,
                              width: width, height: height)

        context.interpolationQuality = .high
        if shadow {
            // Centred and soft: a silhouette, not a lighting effect. Sized off the
            // canvas so it holds up at every icon size.
            context.setShadow(offset: .zero,
                              blur: CGFloat(canvas * shadowBlurFraction),
                              color: CGColor(gray: 0, alpha: CGFloat(shadowAlpha)))
        }
        context.draw(source, in: drawRect)
        return context.makeImage()
    }
}

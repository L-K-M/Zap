import CoreGraphics

/// The pixel operations behind icon substitution: resampling, corner masking, and
/// the one bitmap context every other step draws into.
///
/// Split out of `IconResolver`, which owns the *policy* — what to draw for a
/// bundle ID, when to recompute it, and how to keep that off the ⌘-Tab path.
/// Nothing here has any state, so it's callable from any thread and testable
/// without a cache, a `Preferences` or a screen.
enum IconRenderer {

    /// Corner rounding applied to full-bleed artwork so an un-masked square icon
    /// doesn't read as the only hard-cornered thing on screen (`UNJAILED.md §4.2`).
    /// A fixed fraction of the shorter edge for now — §8.4 wants it on the
    /// Appearance tab alongside the other layout controls.
    static let fullBleedCornerRadiusFraction = 0.225

    /// Pixels an icon needs at `iconSize` points on the sharpest attached display,
    /// rounded up to a whole pixel and never below a floor that keeps a
    /// small-icon-size setting from caching something unusably soft.
    static func pixelSize(forIconSize iconSize: Double, scale: CGFloat) -> Int {
        let pixels = Int((iconSize * Double(max(scale, 1))).rounded(.up))
        return max(IconImageValidator.Limits.warnBelowPixels, pixels)
    }

    /// Resamples `image` so its longest edge is `longestEdge`, never upscaling.
    static func downsample(_ image: CGImage, longestEdge: Int) -> CGImage {
        let sourceLongest = max(image.width, image.height)
        guard longestEdge > 0, sourceLongest > longestEdge else { return image }

        let scale = Double(longestEdge) / Double(sourceLongest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let context = makeContext(width: width, height: height) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage() ?? image
    }

    /// Clips `image` to a rounded rectangle, for full-bleed artwork that would
    /// otherwise be the only hard-cornered thing in the row.
    static func maskingCorners(_ image: CGImage, radiusFraction: Double) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let context = makeContext(width: width, height: height) else {
            return image
        }

        let rect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let radius = CGFloat(radiusFraction) * min(rect.width, rect.height)
        context.interpolationQuality = .high
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    /// An sRGB bitmap context with alpha, so everything downstream — the alpha
    /// classifier included — works in a known colour space (`UNJAILED.md §6.4`).
    static func makeContext(width: Int, height: Int) -> CGContext? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(data: nil, width: width, height: height,
                         bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

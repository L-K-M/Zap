import CoreGraphics

/// The shape family an icon's artwork belongs to, judged from its alpha channel.
///
/// This decides two things: whether substituting the bundle's own artwork is
/// worth doing at all, and whether the result needs Zap's own corner mask so a
/// full-bleed square doesn't read as the only hard-cornered thing on screen.
enum IconShape: String, Equatable, CaseIterable {

    /// The classic Mac icon: a hammer, a compass, a hand. Alpha covers well under
    /// its own bounding box, or rounds off far more than a rounded square would.
    case freeform

    /// A rounded square that fills most of its bounding box — the Big Sur "plate"
    /// and the Tahoe superellipse both land here. See `IconShapeClassifier`'s note
    /// on why those two are one class and not two.
    case roundedSquare

    /// Alpha fills the whole canvas with hard corners. Substituting this unmasked
    /// gives a hard-cornered square, so it wants Zap's own corner mask.
    case fullBleed

    /// No meaningful alpha at all (a fully transparent or unreadable bitmap).
    case empty

    /// Whether swapping this artwork in for the system's icon is worth doing.
    /// Everything with actual ink is worth substituting; only `empty` is not.
    var isWorthSubstituting: Bool { self != .empty }

    /// Whether the substituted artwork should get Zap's own corner rounding.
    var needsCornerMask: Bool { self == .fullBleed }

    /// How Settings describes this artwork on an app's row.
    var label: String {
        switch self {
        case .freeform: return "Original artwork (free-form)"
        case .roundedSquare: return "Original artwork (rounded square)"
        case .fullBleed: return "Original artwork (full-bleed)"
        case .empty: return "No usable artwork"
        }
    }
}

/// Measurements taken off an icon's alpha channel, in units independent of the
/// source's pixel size. Separated from the classification itself so the numbers
/// can be asserted directly in tests.
struct AlphaProfile: Equatable {

    /// Whether any sample reached the ink threshold at all.
    var hasInk: Bool

    /// Fraction of the canvas width spanned by the alpha bounding box, 0...1.
    var boundsWidth: Double

    /// Fraction of the canvas height spanned by the alpha bounding box, 0...1.
    var boundsHeight: Double

    /// Inked samples inside the alpha bounding box, over that box's area. 1 for a
    /// solid rectangle, ~0.79 for a circle.
    var fillRatio: Double

    /// Mean distance from each corner of the alpha bounding box to the first
    /// inked sample along the diagonal toward its centre, as a fraction of the
    /// half-diagonal. 0 for hard corners, ~0.11 for a rounded square, ~0.27 for a
    /// circle.
    var cornerReach: Double

    static let empty = AlphaProfile(hasInk: false, boundsWidth: 0, boundsHeight: 0,
                                    fillRatio: 0, cornerReach: 0)
}

/// Classifies icon artwork by its alpha channel — pure arithmetic over a
/// downsampled bitmap, with no AppKit involvement, so it is unit-testable against
/// synthetic images (`UNJAILED.md §4.2`).
///
/// **Why "plate" and "already squircle" are one class here.** `UNJAILED.md §4.2`
/// asks for those as separate classes, on the theory that Tahoe-native artwork is
/// recognisable and not worth substituting. Measured on the 64² grid this
/// classifier uses, a Big Sur plate (rounded rect, corner radius 0.225 × side) and
/// a Tahoe superellipse differ by **0.6% in fill ratio (0.957 vs 0.951) and not at
/// all in corner reach (0.1133 both)** — well inside the noise of anti-aliasing and
/// resampling, so any threshold splitting them would be a coin flip dressed up as a
/// measurement. They are therefore reported as one `roundedSquare` class.
///
/// The merge costs nothing: both classes take the same action in §4.2's own table
/// (substitute), and substituting genuinely Tahoe-native artwork draws the same
/// picture the system would have drawn from it. The other boundaries are wide —
/// a hard square measures 1.00/0.00 and a circle 0.79/0.27 — and are the ones that
/// change what gets drawn.
enum IconShapeClassifier {

    // MARK: Tuning

    /// Alpha at or above which a sample counts as ink. Deliberately mid-range: the
    /// system's own jail trigger is an edge alpha of 253 (`UNJAILED.md §1`), but
    /// that threshold answers "will macOS mask this", not "where is the artwork".
    static let inkThreshold: UInt8 = 128

    /// Longest edge of the sampling grid. Small enough to be cheap, large enough
    /// that a corner radius resolves to several samples.
    static let sampleResolution = 64

    /// Fraction of the canvas an alpha bounding box must span on both axes to
    /// count as filling it.
    private static let fullCanvasSpan = 0.98

    /// Fill ratio at or above which a shape reads as a solid rectangle.
    private static let solidFillRatio = 0.98

    /// Fill ratio at or above which a shape reads as a rounded square rather than
    /// free-form art. A superellipse measures 0.95 and a circle 0.79.
    private static let roundedSquareFillRatio = 0.88

    /// Corner reach below which corners read as hard.
    private static let hardCornerReach = 0.04

    /// Corner reach below which corners read as rounded-square rather than
    /// circular. A rounded square measures 0.11 and a circle 0.27.
    private static let roundedSquareCornerReach = 0.20

    // MARK: Classification

    /// Classifies `image`, or `.empty` when its alpha can't be read.
    static func classify(_ image: CGImage) -> IconShape {
        guard let profile = profile(of: image) else { return .empty }
        return classify(profile)
    }

    /// Pure classification from an already-measured profile.
    static func classify(_ profile: AlphaProfile) -> IconShape {
        guard profile.hasInk else { return .empty }

        let fillsCanvas = profile.boundsWidth >= fullCanvasSpan
            && profile.boundsHeight >= fullCanvasSpan

        if fillsCanvas
            && profile.fillRatio >= solidFillRatio
            && profile.cornerReach < hardCornerReach {
            return .fullBleed
        }

        if profile.fillRatio >= roundedSquareFillRatio
            && profile.cornerReach < roundedSquareCornerReach {
            return .roundedSquare
        }

        return .freeform
    }

    // MARK: Measurement

    /// Measures `image`'s alpha channel, or `nil` when it can't be rasterised.
    static func profile(of image: CGImage) -> AlphaProfile? {
        guard let mask = AlphaMask(image: image, longestEdge: sampleResolution) else { return nil }
        return profile(of: mask)
    }

    /// Measures an already-sampled alpha mask. Exposed so tests can feed the
    /// arithmetic directly without going through Core Graphics.
    static func profile(of mask: AlphaMask) -> AlphaProfile {
        guard let box = mask.inkBounds(threshold: inkThreshold) else { return .empty }

        let boxWidth = box.maxColumn - box.minColumn + 1
        let boxHeight = box.maxRow - box.minRow + 1

        var inked = 0
        for row in box.minRow...box.maxRow {
            for column in box.minColumn...box.maxColumn where mask.isInk(row: row, column: column, threshold: inkThreshold) {
                inked += 1
            }
        }

        return AlphaProfile(
            hasInk: true,
            boundsWidth: Double(boxWidth) / Double(mask.width),
            boundsHeight: Double(boxHeight) / Double(mask.height),
            fillRatio: Double(inked) / Double(boxWidth * boxHeight),
            cornerReach: mask.cornerReach(in: box, threshold: inkThreshold))
    }
}

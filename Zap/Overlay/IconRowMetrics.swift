import CoreGraphics

/// Shared layout inputs for the horizontally-scrolling icon row, so the SwiftUI
/// view (`OverlayView`) and the controller's scroll math (`OverlayWindowController`)
/// derive their geometry from one source and can't drift apart.
enum IconRowMetrics {
    /// Total horizontal padding around an icon image — 8pt on each side.
    static let cellPadding: CGFloat = 16
    /// Gap between adjacent icon cells.
    static let spacing: CGFloat = 12

    /// The widest bleed the settings allow, mirrored by `Preferences`.
    static let maximumBleed: CGFloat = 0.15

    /// Extent of the icon *image* for a given icon size and bleed.
    ///
    /// Free-form artwork is normalised to equal ink weight (`IconNormalizer`),
    /// which makes its bounding box exceed the nominal icon size — a circle has to
    /// be ~13% wider than a square to carry the same amount of ink. `bleed` is the
    /// headroom allowed for that, as a fraction of the icon size on each side.
    static func imageExtent(iconSize: CGFloat, bleed: CGFloat) -> CGFloat {
        iconSize * (1 + 2 * clampedBleed(bleed))
    }

    /// Footprint of one icon cell (image + padding) for a given icon size and bleed.
    ///
    /// The bleed is spent on the cell's existing 8pt padding first, so at the
    /// default it costs no extra width at all — at `iconSize` 80 and `bleed` 0.08
    /// the image grows to 92.8pt inside a cell that stays 96pt. Only a bleed wide
    /// enough to outgrow the padding widens the row.
    ///
    /// The consequence is that the image is always *contained* by its cell, so
    /// neither of the two clips in the row (`HorizontallyScrollable`'s `.clipped()`
    /// and the panel's `clipShape`) can cut bleeding art. What the art bleeds past
    /// is the selection highlight, which is what reads as the classic Mac look.
    static func cellExtent(iconSize: CGFloat, bleed: CGFloat) -> CGFloat {
        max(imageExtent(iconSize: iconSize, bleed: bleed), iconSize + cellPadding)
    }

    /// Footprint of one icon cell with no bleed — today's geometry.
    static func cellWidth(iconSize: CGFloat) -> CGFloat { cellWidth(iconSize: iconSize, bleed: 0) }

    /// Footprint of one icon cell, bleed included.
    static func cellWidth(iconSize: CGFloat, bleed: CGFloat) -> CGFloat {
        cellExtent(iconSize: iconSize, bleed: bleed)
    }

    /// Bounds a bleed fraction into the supported range, treating non-finite input
    /// from corrupted defaults as none.
    static func clampedBleed(_ bleed: CGFloat) -> CGFloat {
        guard bleed.isFinite else { return 0 }
        return min(max(bleed, 0), maximumBleed)
    }
}

import CoreGraphics

/// Width of the fade band at each edge of the icon row, as a fraction of the
/// viewport. `leading`/`trailing` are 0 at a crisp edge and grow up to the fade
/// ramp's width as content is hidden past that side. The band always fades fully
/// to transparent at the very edge, so a partly-hidden icon never ends in a hard
/// cut — the band just narrows as the edge nears flush.
struct EdgeFade: Equatable {
    var leading: CGFloat
    var trailing: CGFloat

    static let none = EdgeFade(leading: 0, trailing: 0)
}

/// Geometry of the horizontally-scrolling icon row. The row scrolls by a raw pixel
/// `offset` (driven continuously by the scroll wheel and animated by the keyboard),
/// and everything else — how far it can scroll, where a given icon centres, and the
/// edge fade — is a pure function of that offset and the layout. Kept free of any
/// SwiftUI/AppKit state so it can be unit-tested.
struct IconRowGeometry: Equatable {
    /// Number of icons in the row.
    let count: Int
    /// Footprint of one icon (image + padding on each side).
    let cellWidth: CGFloat
    /// Gap between icons.
    let spacing: CGFloat
    /// Visible width of the scrolling row.
    let viewport: CGFloat

    /// Natural (unclipped) width of the whole row.
    var contentWidth: CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * cellWidth + CGFloat(count - 1) * spacing
    }

    /// How far the row can scroll before its trailing edge reaches the viewport.
    var maxScroll: CGFloat { max(0, contentWidth - viewport) }

    /// Whether the row is wider than the viewport (and so scrolls / fades at all).
    var overflows: Bool { viewport > 0 && maxScroll > 0 }

    /// Bounds an offset to the scrollable range.
    func clamp(_ offset: CGFloat) -> CGFloat { min(max(offset, 0), maxScroll) }

    /// Offset that centres `index`, clamped so the row never scrolls past its ends.
    func centeredOffset(forIndex index: Int) -> CGFloat {
        guard overflows else { return 0 }
        let i = min(max(index, 0), count - 1)
        let centre = CGFloat(i) * (cellWidth + spacing) + cellWidth / 2
        return clamp(centre - viewport / 2)
    }

    /// Edge fade for a given scroll `offset`: a soft band that fades fully to
    /// transparent at any edge with content hidden past it, so the clip reads as a
    /// deliberate soft edge rather than a hard cut. Each band is at most the fade
    /// ramp wide but narrows to the amount of content actually hidden on that side,
    /// so it shrinks to nothing — leaving a flush first/last icon crisp — instead of
    /// hardening into an opaque edge over the last hidden sliver.
    func fade(offset: CGFloat, fadeWidth: CGFloat) -> EdgeFade {
        guard overflows else { return .none }
        let scrolled = clamp(offset)
        let ramp = min(max(fadeWidth, 1), viewport / 3)
        return EdgeFade(
            leading: min(ramp, scrolled) / viewport,
            trailing: min(ramp, maxScroll - scrolled) / viewport
        )
    }
}

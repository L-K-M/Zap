import SwiftUI

/// Draws a `DecorationStyle` as a set of parallel diagonal stripes hugging one of
/// the panel's top corners — the Sinclair ZX Spectrum look.
///
/// The canvas fills the whole panel and each stripe is deliberately overshot
/// *past* the two panel edges; the panel's rounded clip then trims the stripes
/// flush to its boundary. Overshooting avoids the triangular gaps you'd otherwise
/// get where a 45° butt-capped stripe meets an edge, so the bands fill right up to
/// the rounded corner with no gaps. The band is inset from the corner in step with
/// `cornerRadius`, so the more rounded the panel, the further in it starts.
struct PanelDecoration: View {
    let style: DecorationStyle
    let position: DecorationPosition
    /// The panel's corner radius, so the band starts clear of the rounded corner.
    let cornerRadius: CGFloat
    /// Thickness of each individual band.
    let thickness: CGFloat

    var body: some View {
        Canvas { context, size in
            let colors = style.colors
            guard !colors.isEmpty else { return }

            let trailing = position == .topTrailing
            let corner = CGPoint(x: trailing ? size.width : 0, y: 0)

            // Stripe axis runs parallel to the corner chamfer; the inward normal
            // steps successive stripes toward the panel interior.
            let invSqrt2 = 1 / 2.0.squareRoot()
            let axis = CGVector(dx: (trailing ? 1 : -1) * invSqrt2, dy: invSqrt2)
            let inward = CGVector(dx: (trailing ? -1 : 1) * invSqrt2, dy: invSqrt2)

            // A pitch equal to the thickness gives solid, gapless bands. The
            // overshoot pushes each stripe past both edges so the clip — not the
            // butt cap — defines the flush edge.
            let pitch = thickness
            let overshoot = thickness * 1.8
            // Distance along the diagonal from the sharp corner to the rounded
            // edge's nearest point, so the first band clears the rounding.
            let cornerInset = cornerRadius * (2.0.squareRoot() - 1)

            for (index, color) in colors.enumerated() {
                let distance = cornerInset + thickness / 2 + CGFloat(index) * pitch
                let center = CGPoint(x: corner.x + inward.dx * distance,
                                     y: corner.y + inward.dy * distance)
                // Half-length reaches the edges (= distance for a right-angled
                // corner) plus an overshoot beyond them.
                let halfLength = distance + overshoot
                var path = Path()
                path.move(to: CGPoint(x: center.x - axis.dx * halfLength,
                                      y: center.y - axis.dy * halfLength))
                path.addLine(to: CGPoint(x: center.x + axis.dx * halfLength,
                                         y: center.y + axis.dy * halfLength))
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: thickness, lineCap: .butt))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

import SwiftUI

/// An optional retro CRT effect drawn over the whole panel: faint horizontal
/// scanlines plus a soft vignette that darkens toward the edges, as if the panel
/// were a slightly bulged phosphor screen. Purely decorative — never hit-tests —
/// and scaled by `intensity` (0...1) so it can be as subtle or as loud as the user
/// likes. Clipped to the panel's rounded rect so it doesn't bleed past the corners.
struct CRTScreenOverlay: View {
    /// Strength of the effect, 0 (off) ... 1 (strong).
    let intensity: Double
    /// The panel's corner radius, to match the clip.
    let cornerRadius: CGFloat

    var body: some View {
        Canvas { context, size in
            // Scanlines: a thin dark line every few points.
            let lineGap: CGFloat = 3
            let lineOpacity = 0.08 + 0.30 * intensity
            var y: CGFloat = 0
            while y < size.height {
                let line = CGRect(x: 0, y: y, width: size.width, height: 1)
                context.fill(Path(line), with: .color(.black.opacity(lineOpacity)))
                y += lineGap
            }

            // Vignette: transparent in the middle, darkening toward the edges.
            let edge = 0.04 + 0.26 * intensity
            let vignette = Gradient(colors: [.clear, .black.opacity(edge)])
            let maxDimension = max(size.width, size.height)
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(vignette,
                                      center: CGPoint(x: size.width / 2, y: size.height / 2),
                                      startRadius: maxDimension * 0.2,
                                      endRadius: maxDimension * 0.7)
            )
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

import SwiftUI

/// The Commodore Amiga "boing ball": a red-and-white checkered sphere, nestled in
/// one of the panel's top corners. Companion to `PanelDecoration` (the stripe
/// styles) for `DecorationStyle.amiga`.
///
/// The checker is a genuine spherical mapping rather than a flat grid: for each
/// sample inside the disc we recover the front-hemisphere point of a unit sphere
/// (orthographic inverse), read its longitude/latitude, and pick red or white from
/// a lat/long checkerboard. A slight tilt leans the poles like the original, and a
/// rim-darkening shade gives it volume. Drawn into a `Canvas` and clipped to a
/// circle, so the chunky sample grid reads as a clean ball with a pleasingly
/// pixelated surface.
struct BoingBallDecoration: View {
    /// Which top corner the ball sits in.
    let position: DecorationPosition
    /// The panel's corner radius, so the ball clears the rounded corner.
    let cornerRadius: CGFloat
    /// The ball's diameter in points.
    let diameter: CGFloat

    // The classic boing-ball red (leaning magenta) and white.
    private let red = (r: 0.85, g: 0.10, b: 0.22)
    /// Lean of the poles, in radians.
    private let tilt = -0.32
    /// Number of checker segments around the sphere (longitude) and pole-to-pole
    /// (latitude). The original used 16 × 8.
    private let segments = 8.0

    var body: some View {
        Canvas { context, size in
            let radius = diameter / 2
            // Inset from the corner so the ball clears the rounded edge, scaling the
            // inset gently with the corner radius (as the stripes do).
            let inset = cornerRadius * 0.5 + 6
            let centerX = position == .topTrailing ? size.width - inset - radius : inset + radius
            let center = CGPoint(x: centerX, y: inset + radius)

            // Clean circular edge over the chunky sample grid.
            let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                              width: diameter, height: diameter))
            context.clip(to: disc)

            // Sample the disc on a grid; each cell is one pixel of the ball's
            // surface. A handful of samples per radius is plenty at this size.
            let step = max(1, diameter / 40)
            let segment = Double.pi / segments
            var x = -radius
            while x <= radius {
                var y = -radius
                while y <= radius {
                    let nx = Double(x / radius)
                    let ny = Double(y / radius)
                    let r2 = nx * nx + ny * ny
                    if r2 <= 1 {
                        let nz = (1 - r2).squareRoot()
                        // Lean the ball by rotating the sample in the view plane.
                        let lx = nx * cos(tilt) - ny * sin(tilt)
                        let ly = nx * sin(tilt) + ny * cos(tilt)
                        let longitude = atan2(lx, nz)
                        let latitude = asin(min(1, max(-1, ly)))
                        let checker = (Int(floor(longitude / segment)) + Int(floor(latitude / segment))) & 1
                        // Rim-darkening for volume: full bright facing the viewer
                        // (nz≈1), down to ~half at the silhouette.
                        let shade = 0.5 + 0.5 * nz
                        let color: Color = checker == 0
                            ? Color(red: red.r * shade, green: red.g * shade, blue: red.b * shade)
                            : Color(white: shade)
                        let cell = CGRect(x: center.x + x, y: center.y + y, width: step, height: step)
                        context.fill(Path(cell), with: .color(color))
                    }
                    y += step
                }
                x += step
            }

            // A soft outline so the ball reads against a light panel too.
            context.stroke(disc, with: .color(.black.opacity(0.25)), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

import SwiftUI
import CoreGraphics
import Foundation

/// The Commodore Amiga "boing ball": a red-and-white checkered sphere tucked into
/// one of the panel's top corners — the disc overshoots the two panel edges and
/// the panel's rounded clip trims it flush, the same treatment the stripe styles
/// get (see `PanelDecoration`). Companion to those for `DecorationStyle.amiga`.
///
/// The checker is a genuine spherical mapping rather than a flat grid: each pixel
/// inside the disc is mapped back to the front hemisphere of a unit sphere
/// (orthographic inverse), and its longitude/latitude picks red or white from a
/// lat/long checkerboard. Like the original demo, the shading is **flat** — the
/// sphere illusion comes entirely from the checker distortion — and the poles
/// lean to the right.
///
/// Two renditions share that math. The **smooth** ball is rasterized at full
/// display scale with 2×2 supersampling — smooth checker edges and silhouette.
/// The **pixelated** ball is a copy of the original demo's look: rasterized at a
/// fixed low resolution with hard edges and scaled up with interpolation off, so
/// the chunky pixels and stair-stepped silhouette read just like the demo.
/// Either bitmap is cached, so re-renders of the overlay never re-rasterize it
/// on the hot path.
struct BoingBallDecoration: View {
    /// Which top corner the ball sits in.
    let position: DecorationPosition
    /// The panel's corner radius, so the ball clears the rounded corner.
    let cornerRadius: CGFloat
    /// The ball's diameter in points.
    let diameter: CGFloat
    /// Render the original demo's chunky low-res look instead of the smooth ball.
    let pixelated: Bool

    @Environment(\.displayScale) private var displayScale

    // The vivid boing-ball red of the original demo.
    private static let red = (r: 0.95, g: 0.10, b: 0.12)
    /// Lean of the poles, in radians — positive tips them to the right, matching
    /// the original demo.
    private static let tilt = 0.32
    /// Checker bands are π/8 wide in longitude and latitude, so the visible front
    /// hemisphere shows 8 × 8 — the proportions of the original's 16 × 8 sphere.
    private static let segments = 8.0

    var body: some View {
        // Resolve (or reuse) the rasterized sphere here in `body`, not inside the
        // Canvas closure, so the static cache is only touched on the main thread.
        let sphere = Self.sphereImage(diameter: diameter, scale: displayScale,
                                      pixelated: pixelated)
        Canvas { context, size in
            let radius = diameter / 2
            // Tuck the ball into the corner: most of the disc inside the panel, the
            // rest overshooting the two edges for the rounded clip to trim flush.
            let center = Self.center(in: size, position: position,
                                     cornerRadius: cornerRadius, radius: radius)
            let frame = CGRect(x: center.x - radius, y: center.y - radius,
                               width: diameter, height: diameter)
            if let sphere {
                context.draw(sphere, in: frame)
            }
            // A soft outline so the smooth ball reads against a light panel too.
            // The pixelated ball keeps its bare stair-stepped silhouette — a
            // smooth circle around it would clash, and the original had none.
            if !pixelated {
                context.stroke(Path(ellipseIn: frame),
                               with: .color(.black.opacity(0.25)), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    /// Centre of the ball, sitting on the corner's 45° diagonal so the disc
    /// occupies the corner like the stripe decorations: pushed inward of the
    /// rounded edge (the same `cornerRadius·(√2 − 1)` inset the stripes use) by
    /// most of a radius, leaving the rest of the disc to overshoot both panel
    /// edges and be trimmed flush by the panel's clip. Pure, for unit testing.
    static func center(in size: CGSize, position: DecorationPosition,
                       cornerRadius: CGFloat, radius: CGFloat) -> CGPoint {
        let cornerInset = cornerRadius * (2.0.squareRoot() - 1)
        let diagonal = cornerInset + radius * 0.8
        let perAxis = diagonal / 2.0.squareRoot()
        let x = position == .topTrailing ? size.width - perAxis : perAxis
        return CGPoint(x: x, y: perAxis)
    }

    // MARK: Sphere rasterization

    /// Raster width of the pixelated ball, independent of its on-screen size. The
    /// original demo's ball was ~144 pixels across; at the decoration's smaller
    /// visual size, 96 reproduces the same perceived chunkiness when scaled up
    /// with interpolation off.
    private static let pixelatedResolution = 96

    /// The last-rendered sphere of each rendition. `body` re-runs on every
    /// selection change while the overlay is up; one cached image makes that free,
    /// where re-rasterizing ~100k pixels per Tab press would be wasted work on the
    /// switcher hot path. Read and written only from `body` (main thread).
    private static var cachedSmooth: (pixelDiameter: Int, image: Image)?
    private static var cachedPixelated: Image?

    /// The checkered sphere as an `Image`: rasterized at `scale` so it stays
    /// crisp on Retina displays, or — when `pixelated` — at the fixed low
    /// resolution with interpolation off so the chunky pixels survive scaling.
    /// Cached per rendition.
    static func sphereImage(diameter: CGFloat, scale: CGFloat, pixelated: Bool) -> Image? {
        if pixelated {
            if let cached = cachedPixelated { return cached }
            guard let bitmap = renderSphere(pixelDiameter: pixelatedResolution,
                                            antialiased: false) else { return nil }
            let image = Image(decorative: bitmap, scale: 1).interpolation(.none)
            cachedPixelated = image
            return image
        }
        let effectiveScale = max(1, scale)
        let pixelDiameter = max(8, Int((diameter * effectiveScale).rounded()))
        if let cached = cachedSmooth, cached.pixelDiameter == pixelDiameter {
            return cached.image
        }
        guard let bitmap = renderSphere(pixelDiameter: pixelDiameter,
                                        antialiased: true) else { return nil }
        let image = Image(decorative: bitmap, scale: effectiveScale)
        cachedSmooth = (pixelDiameter, image)
        return image
    }

    /// Rasterizes the sphere into a premultiplied-RGBA bitmap. Antialiased, each
    /// pixel is sampled at 2×2 subpixel offsets: subsample coverage becomes alpha
    /// (anti-aliasing the silhouette) and interior checker edges average toward
    /// smooth. Otherwise one centre sample per pixel gives the hard edges of the
    /// pixelated rendition.
    static func renderSphere(pixelDiameter n: Int, antialiased: Bool) -> CGImage? {
        guard n > 0 else { return nil }
        let radius = Double(n) / 2
        let segment = Double.pi / segments
        let offsets: [(Double, Double)] = antialiased
            ? [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
            : [(0.5, 0.5)]
        let sampleCount = Double(offsets.count)
        var pixels = [UInt8](repeating: 0, count: n * n * 4)

        for py in 0..<n {
            for px in 0..<n {
                var r = 0.0, g = 0.0, b = 0.0
                var covered = 0
                for (ox, oy) in offsets {
                    let nx = (Double(px) + ox - radius) / radius
                    let ny = (Double(py) + oy - radius) / radius
                    let r2 = nx * nx + ny * ny
                    guard r2 <= 1 else { continue }
                    let nz = (1 - r2).squareRoot()
                    // Lean the ball by rotating the sample in the view plane.
                    let lx = nx * cos(tilt) - ny * sin(tilt)
                    let ly = nx * sin(tilt) + ny * cos(tilt)
                    let longitude = atan2(lx, nz)
                    let latitude = asin(min(1, max(-1, ly)))
                    let checker = (Int(floor(longitude / segment)) + Int(floor(latitude / segment))) & 1
                    // Flat shading, like the original: no rim darkening — the
                    // sphere reads as 3D from the checker distortion alone.
                    if checker == 0 {
                        r += red.r; g += red.g; b += red.b
                    } else {
                        r += 1; g += 1; b += 1
                    }
                    covered += 1
                }
                guard covered > 0 else { continue }
                // Premultiplied components: the sum over the subsamples divided by
                // their count is exactly (average color × coverage alpha), since
                // uncovered subsamples contribute zero.
                let i = (py * n + px) * 4
                pixels[i]     = UInt8((min(1, r / sampleCount) * 255).rounded())
                pixels[i + 1] = UInt8((min(1, g / sampleCount) * 255).rounded())
                pixels[i + 2] = UInt8((min(1, b / sampleCount) * 255).rounded())
                pixels[i + 3] = UInt8((Double(covered) / sampleCount * 255).rounded())
            }
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: n, height: n,
                      bitsPerComponent: 8, bytesPerRow: n * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .makeImage()
        }
    }
}

import CoreGraphics

/// A small grid of alpha samples taken off a `CGImage`, used to reason about an
/// icon's shape without keeping the full-resolution bitmap around.
///
/// The grid keeps the source's aspect ratio (a 2:1 image samples into a 2:1 grid),
/// so a shape's proportions survive the downsample. Row 0 is whichever edge Core
/// Graphics drew first; every measurement here is symmetric under flipping, so it
/// makes no difference which.
struct AlphaMask: Equatable {

    /// A rectangle of grid cells, inclusive on all four edges.
    struct InkBounds: Equatable {
        let minRow: Int
        let maxRow: Int
        let minColumn: Int
        let maxColumn: Int

        var rowCount: Int { maxRow - minRow + 1 }
        var columnCount: Int { maxColumn - minColumn + 1 }
    }

    let width: Int
    let height: Int

    /// Row-major alpha samples, `width * height` of them.
    let samples: [UInt8]

    /// How finely the diagonal is walked when measuring corner reach. Finer than
    /// the grid so the measurement isn't quantised to whole cells.
    private static let diagonalSteps = 256

    /// Builds a mask from raw samples, or `nil` when the dimensions don't match.
    /// Exposed so tests can measure synthetic shapes without Core Graphics.
    init?(width: Int, height: Int, samples: [UInt8]) {
        guard width > 0, height > 0, samples.count == width * height else { return nil }
        self.width = width
        self.height = height
        self.samples = samples
    }

    /// Samples `image`'s alpha channel onto a grid whose longest edge is
    /// `longestEdge`, or `nil` when it can't be rasterised.
    init?(image: CGImage, longestEdge: Int) {
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0, longestEdge >= 8 else { return nil }

        let longest = Swift.max(sourceWidth, sourceHeight)
        let gridWidth = Swift.max(1, Int((Double(sourceWidth) / Double(longest) * Double(longestEdge)).rounded()))
        let gridHeight = Swift.max(1, Int((Double(sourceHeight) / Double(longest) * Double(longestEdge)).rounded()))

        // Core Graphics has no Swift-expressible alpha-only bitmap context (the
        // colour space parameter is non-optional, and alpha-only requires none),
        // so sample into RGBA and keep the alpha byte.
        var rgba = [UInt8](repeating: 0, count: gridWidth * gridHeight * 4)
        let drawn: Bool = rgba.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(data: base,
                                          width: gridWidth,
                                          height: gridHeight,
                                          bitsPerComponent: 8,
                                          bytesPerRow: gridWidth * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            let rect = CGRect(x: 0, y: 0, width: CGFloat(gridWidth), height: CGFloat(gridHeight))
            context.interpolationQuality = .high
            context.clear(rect)
            context.draw(image, in: rect)
            return true
        }
        guard drawn else { return nil }

        var alpha = [UInt8](repeating: 0, count: gridWidth * gridHeight)
        for index in 0..<(gridWidth * gridHeight) {
            alpha[index] = rgba[index * 4 + 3]
        }

        self.width = gridWidth
        self.height = gridHeight
        self.samples = alpha
    }

    // MARK: Measurements

    /// Whether the sample at `row`/`column` reaches `threshold`. Out-of-range
    /// coordinates read as empty.
    func isInk(row: Int, column: Int, threshold: UInt8) -> Bool {
        guard row >= 0, row < height, column >= 0, column < width else { return false }
        return samples[row * width + column] >= threshold
    }

    /// The tightest cell rectangle containing every inked sample, or `nil` when
    /// nothing reaches `threshold`.
    func inkBounds(threshold: UInt8) -> InkBounds? {
        var minRow = Int.max
        var maxRow = Int.min
        var minColumn = Int.max
        var maxColumn = Int.min

        for row in 0..<height {
            for column in 0..<width where samples[row * width + column] >= threshold {
                minRow = Swift.min(minRow, row)
                maxRow = Swift.max(maxRow, row)
                minColumn = Swift.min(minColumn, column)
                maxColumn = Swift.max(maxColumn, column)
            }
        }

        guard minRow <= maxRow, minColumn <= maxColumn else { return nil }
        return InkBounds(minRow: minRow, maxRow: maxRow, minColumn: minColumn, maxColumn: maxColumn)
    }

    /// Mean distance from each corner of `box` to the first inked sample along the
    /// diagonal toward its centre, as a fraction of the half-diagonal.
    ///
    /// 0 means the corners are hard; a rounded square measures about 0.11 and a
    /// circle about 0.27. A corner that never reaches ink contributes 1.
    func cornerReach(in box: InkBounds, threshold: UInt8) -> Double {
        let centreRow = Double(box.minRow + box.maxRow) / 2
        let centreColumn = Double(box.minColumn + box.maxColumn) / 2
        let corners = [(box.minRow, box.minColumn), (box.minRow, box.maxColumn),
                       (box.maxRow, box.minColumn), (box.maxRow, box.maxColumn)]

        var total = 0.0
        for (cornerRow, cornerColumn) in corners {
            var reach = 1.0
            for step in 0...Self.diagonalSteps {
                let t = Double(step) / Double(Self.diagonalSteps)
                let row = Int((Double(cornerRow) + (centreRow - Double(cornerRow)) * t).rounded())
                let column = Int((Double(cornerColumn) + (centreColumn - Double(cornerColumn)) * t).rounded())
                if isInk(row: row, column: column, threshold: threshold) {
                    reach = t
                    break
                }
            }
            total += reach
        }
        return total / Double(corners.count)
    }
}

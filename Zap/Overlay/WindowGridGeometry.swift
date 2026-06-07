import CoreGraphics

/// Geometry of the window-preview grid: how `count` windows tile into columns and
/// rows within an available width, and the pixel size of the resulting block.
///
/// Pure (no SwiftUI/AppKit state) so it can be unit-tested and shared between the
/// overlay view (which lays the grid out) and the controller (which needs the
/// column count to drive arrow-key navigation). The column count is a roughly
/// square arrangement, capped by how many cells fit across the available width and
/// never exceeding the window count.
struct WindowGridGeometry: Equatable {
    /// Number of windows in the grid.
    let count: Int
    /// Width the grid may occupy before it would overflow (from the target screen).
    let availableWidth: CGFloat
    /// Footprint of one cell (thumbnail + padding).
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    /// Gap between cells, used both horizontally and vertically.
    let spacing: CGFloat

    /// Number of columns: roughly `ceil(sqrt(count))` for a balanced block, but no
    /// more than fit across `availableWidth`, and never more than `count`.
    var columns: Int {
        guard count > 0 else { return 0 }
        let countF = CGFloat(count)
        let perCell = cellWidth + spacing
        // Prefer a square-ish grid so the block stays compact rather than a long strip.
        let square = max(1, Int(Double(count).squareRoot().rounded(.up)))
        // Cap by width. Clamp the raw value to `count` *before* converting to Int so a
        // huge/unset availableWidth (e.g. `.greatestFiniteMagnitude`) can't trap.
        let rawFitting: CGFloat = perCell > 0 ? (availableWidth + spacing) / perCell : countF
        let fitting = rawFitting.isFinite ? max(1, Int(min(rawFitting, countF))) : count
        return max(1, min(square, fitting, count))
    }

    /// Number of rows the columns wrap into.
    var rows: Int {
        let c = columns
        guard c > 0 else { return 0 }
        return (count + c - 1) / c
    }

    /// Natural width of the laid-out grid.
    var width: CGFloat {
        let c = CGFloat(columns)
        guard c > 0 else { return 0 }
        return c * cellWidth + (c - 1) * spacing
    }

    /// Natural height of the laid-out grid (before any scroll cap).
    var height: CGFloat {
        let r = CGFloat(rows)
        guard r > 0 else { return 0 }
        return r * cellHeight + (r - 1) * spacing
    }
}

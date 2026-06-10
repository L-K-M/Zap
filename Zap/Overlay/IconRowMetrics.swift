import CoreGraphics

/// Shared layout inputs for the horizontally-scrolling icon row, so the SwiftUI
/// view (`OverlayView`) and the controller's scroll math (`OverlayWindowController`)
/// derive their geometry from one source and can't drift apart.
enum IconRowMetrics {
    /// Total horizontal padding around an icon image — 8pt on each side.
    static let cellPadding: CGFloat = 16
    /// Gap between adjacent icon cells.
    static let spacing: CGFloat = 12
    /// Footprint of one icon cell (image + padding) for a given icon size.
    static func cellWidth(iconSize: CGFloat) -> CGFloat { iconSize + cellPadding }
}

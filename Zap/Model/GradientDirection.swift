import Foundation

/// The direction of the switcher's background gradient.
///
/// Each case exposes a `start`/`end` pair expressed as offsets from the panel's
/// top-center anchor: `x` is a fraction of the reference width in `[-0.5, 0.5]`
/// and `y` a fraction of the reference height in `[0, 1]`. `OverlayView` turns
/// these into `UnitPoint`s against the *current* panel size so the gradient line
/// stays pinned to a fixed reference rect — keeping the gradient's appearance
/// stable as the panel grows (see `OverlayView.backgroundFill`).
enum GradientDirection: String, CaseIterable, Identifiable {
    case topToBottom
    case bottomToTop
    case leadingToTrailing
    case trailingToLeading
    case topLeadingToBottomTrailing
    case topTrailingToBottomLeading

    var id: String { rawValue }

    /// Human-readable name for the settings picker.
    var label: String {
        switch self {
        case .topToBottom: return "Top to bottom"
        case .bottomToTop: return "Bottom to top"
        case .leadingToTrailing: return "Left to right"
        case .trailingToLeading: return "Right to left"
        case .topLeadingToBottomTrailing: return "Top-left to bottom-right"
        case .topTrailingToBottomLeading: return "Top-right to bottom-left"
        }
    }

    /// Gradient line start, as a top-center–anchored reference offset.
    var start: CGPoint {
        switch self {
        case .topToBottom: return CGPoint(x: 0, y: 0)
        case .bottomToTop: return CGPoint(x: 0, y: 1)
        case .leadingToTrailing: return CGPoint(x: -0.5, y: 0)
        case .trailingToLeading: return CGPoint(x: 0.5, y: 0)
        case .topLeadingToBottomTrailing: return CGPoint(x: -0.5, y: 0)
        case .topTrailingToBottomLeading: return CGPoint(x: 0.5, y: 0)
        }
    }

    /// Gradient line end, as a top-center–anchored reference offset.
    var end: CGPoint {
        switch self {
        case .topToBottom: return CGPoint(x: 0, y: 1)
        case .bottomToTop: return CGPoint(x: 0, y: 0)
        case .leadingToTrailing: return CGPoint(x: 0.5, y: 0)
        case .trailingToLeading: return CGPoint(x: -0.5, y: 0)
        case .topLeadingToBottomTrailing: return CGPoint(x: 0.5, y: 1)
        case .topTrailingToBottomLeading: return CGPoint(x: -0.5, y: 1)
        }
    }
}

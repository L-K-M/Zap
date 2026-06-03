import SwiftUI
import AppKit
import CoreGraphics

/// Observable state shared between the switcher and the overlay view. Updating
/// `selectedIndex` only moves the highlight — it does not rebuild the window.
final class OverlayModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var selectedIndex: Int = 0

    /// Horizontal scroll position of the icon row, in points. Driven continuously by
    /// the scroll wheel and animated by keyboard navigation (which centres the
    /// selection) — never by mouse hover, so pointing at an icon merely highlights it
    /// instead of scrolling it out from under the cursor. Also drives the edge fade,
    /// which tracks the real scroll position rather than the highlight.
    @Published var scrollOffset: CGFloat = 0

    /// Process ids the user asked to quit that we're still verifying. Their icons
    /// render dimmed and the selection skips over them until we know whether they
    /// actually quit (then removed) or refused (then restored to full opacity).
    @Published var quittingPIDs: Set<pid_t> = []

    /// Windows of the currently-selected app, revealed after a dwell. Empty when
    /// the window list is hidden.
    @Published var windows: [WindowInfo] = []
    /// The highlighted window, or `nil` when the app row itself is focused.
    @Published var windowSelectedIndex: Int?

    /// Captured previews keyed by `CGWindowID`, populated asynchronously after the
    /// window list appears. A missing entry means "not (yet) available" — the row
    /// falls back to its placeholder glyph.
    @Published var windowThumbnails: [CGWindowID: NSImage] = [:]

    /// Maximum width the icon row may occupy before it scrolls horizontally.
    /// Set from the target screen so the panel never runs off-screen.
    @Published var maxContentWidth: CGFloat = .greatestFiniteMagnitude

    /// Called when the user clicks an icon. The argument is the app's index.
    var onPick: ((Int) -> Void)?
    /// Called when the pointer hovers an app icon. The argument is the app's index.
    var onHoverApp: ((Int) -> Void)?
    /// Called when the user clicks a window row. The argument is the window's index.
    var onPickWindow: ((Int) -> Void)?
    /// Called when the pointer hovers a window row. The argument is the window's index.
    var onHoverWindow: ((Int) -> Void)?

    var selectedApp: AppInfo? {
        apps.indices.contains(selectedIndex) ? apps[selectedIndex] : nil
    }
}

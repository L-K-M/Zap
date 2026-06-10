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

    /// Bumped each time *keyboard* navigation moves the window selection, so the
    /// overlay can scroll the highlighted window into view. Hover updates the
    /// selection without bumping this, so merely pointing at a window never scrolls
    /// the list out from under the cursor.
    @Published var windowScrollTick: Int = 0

    /// Captured previews keyed by `CGWindowID`, populated asynchronously after the
    /// window list appears. A missing entry means "not (yet) available" — the row
    /// falls back to its placeholder glyph.
    @Published var windowThumbnails: [CGWindowID: NSImage] = [:]

    /// Maximum width the icon row may occupy before it scrolls horizontally.
    /// Set from the target screen so the panel never runs off-screen.
    @Published var maxContentWidth: CGFloat = .greatestFiniteMagnitude

    /// Maximum height the whole panel may occupy. Once the window list is showing
    /// this is the space from the panel's fixed top edge down to the bottom of the
    /// screen, so the panel only ever grows *downward* and the window list/grid
    /// scrolls internally once it reaches the bottom — the top never shifts up.
    /// `.greatestFiniteMagnitude` until `layout` sets it, so the panel is
    /// unconstrained before it's first sized.
    @Published var maxPanelHeight: CGFloat = .greatestFiniteMagnitude

    /// The icon a file drag is currently hovering over, highlighted as a drop target.
    @Published var dropTargetIndex: Int?

    /// The current type-to-search query, shown as a small badge while the user
    /// types to jump the selection. Empty when no query is active.
    @Published var typeQuery: String = ""

    /// Called when the user clicks an icon. The argument is the app's index.
    var onPick: ((Int) -> Void)?
    /// Called when the pointer hovers an app icon. The argument is the app's index.
    var onHoverApp: ((Int) -> Void)?
    /// Called when the user clicks a window row. The argument is the window's index.
    var onPickWindow: ((Int) -> Void)?
    /// Called when the pointer hovers a window row. The argument is the window's index.
    var onHoverWindow: ((Int) -> Void)?
    /// Called when files are dropped on an app icon. Arguments: the app's index and
    /// the dropped file URLs.
    var onDropFiles: ((Int, [URL]) -> Void)?

    var selectedApp: AppInfo? {
        apps.indices.contains(selectedIndex) ? apps[selectedIndex] : nil
    }
}

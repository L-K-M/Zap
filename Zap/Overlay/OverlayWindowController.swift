import AppKit
import SwiftUI

/// An `NSHostingView` that accepts the first mouse click even when its window is
/// not key, so a click on the (background-app) overlay registers immediately.
private final class OverlayHostingView: NSHostingView<OverlayView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the borderless overlay window and keeps it positioned and sized to the
/// SwiftUI content. Shows across all Spaces and over fullscreen apps.
final class OverlayWindowController {

    let model = OverlayModel()
    private let window: NSWindow
    private let hostingView: OverlayHostingView

    private(set) var isVisible = false

    /// The screen the overlay is currently anchored to.
    private var currentScreen: NSScreen?
    /// The window's top edge (AppKit coordinates). Kept fixed as the panel grows
    /// downward when the window list appears, so the switcher row doesn't jump.
    private var anchorTop: CGFloat?

    /// Invoked when the user clicks an app icon. Argument is the app's index.
    var onPick: ((Int) -> Void)? {
        get { model.onPick }
        set { model.onPick = newValue }
    }

    /// Invoked when the pointer hovers an app icon. Argument is the app's index.
    var onHoverApp: ((Int) -> Void)? {
        get { model.onHoverApp }
        set { model.onHoverApp = newValue }
    }

    /// Invoked when the user clicks a window row. Argument is the window's index.
    var onPickWindow: ((Int) -> Void)? {
        get { model.onPickWindow }
        set { model.onPickWindow = newValue }
    }

    /// Invoked when the pointer hovers a window row. Argument is the window's index.
    var onHoverWindow: ((Int) -> Void)? {
        get { model.onHoverWindow }
        set { model.onHoverWindow = newValue }
    }

    init(preferences: Preferences) {
        hostingView = OverlayHostingView(rootView: OverlayView(model: model, preferences: preferences))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Host the SwiftUI view inside a plain container rather than using it as
        // the window's `contentView` directly. As a `contentView`, an
        // `NSHostingView` drives the window's size from its content and resizes
        // it from the bottom-left origin — which shoved the panel rightward when
        // the window list appeared. A plain container has no intrinsic size, so
        // the window frame is controlled solely by `layout(keepTop:)`.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        container.autoresizesSubviews = true
        hostingView.frame = container.bounds
        container.addSubview(hostingView)
        window.contentView = container
    }

    // MARK: Presentation

    func show(apps: [AppInfo], selectedIndex: Int, on screen: NSScreen) {
        model.apps = apps
        model.selectedIndex = selectedIndex
        model.windows = []
        model.windowSelectedIndex = nil
        model.windowThumbnails = [:]

        currentScreen = screen
        layout(keepTop: false)
        window.orderFrontRegardless()
        isVisible = true
    }

    func updateSelection(_ index: Int) {
        model.selectedIndex = index
    }

    // MARK: Window list

    /// Replaces the window list and re-lays-out the panel keeping its top fixed.
    func setWindows(_ windows: [WindowInfo], selected: Int?) {
        model.windows = windows
        model.windowSelectedIndex = selected
        model.windowThumbnails = [:]
        layout(keepTop: true)
    }

    func updateWindowSelection(_ index: Int?) {
        model.windowSelectedIndex = index
    }

    /// Stores a captured preview for `windowID`. Ignored if that window is no
    /// longer listed, so a late-arriving capture can't repopulate a stale row.
    func setWindowThumbnail(_ image: NSImage, for windowID: CGWindowID) {
        guard model.windows.contains(where: { $0.cgWindowID == windowID }) else { return }
        model.windowThumbnails[windowID] = image
    }

    /// Removes the window list (if shown) and shrinks the panel back.
    func clearWindows() {
        guard !model.windows.isEmpty else { return }
        model.windows = []
        model.windowSelectedIndex = nil
        model.windowThumbnails = [:]
        layout(keepTop: true)
    }

    func hide() {
        guard isVisible else { return }
        window.orderOut(nil)
        isVisible = false
        model.apps = []
        model.selectedIndex = 0
        model.windows = []
        model.windowSelectedIndex = nil
        model.windowThumbnails = [:]
        anchorTop = nil
        currentScreen = nil
    }

    // MARK: Layout

    private func layout(keepTop: Bool) {
        guard let screen = currentScreen else { return }
        let visible = screen.visibleFrame

        // Cap how wide the icon row may grow before it scrolls, leaving a margin
        // so the panel never butts against the screen edges.
        let horizontalMargin: CGFloat = 40
        model.maxContentWidth = max(120, visible.width - horizontalMargin * 2)

        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let size = NSSize(
            width: min(max(fitting.width, 80), visible.width - horizontalMargin),
            height: min(max(fitting.height, 80), visible.height)
        )

        let originY: CGFloat
        if keepTop, let top = anchorTop {
            // Grow/shrink downward from the fixed top edge.
            originY = top - size.height
        } else {
            // Position the panel about two-thirds up the screen; in AppKit
            // coordinates y grows upward, so 2/3 of the height from the bottom
            // places the window's center above the midline.
            let centerY = visible.minY + visible.height * (2.0 / 3.0)
            originY = centerY - size.height / 2
        }

        // Clamp the frame so it stays fully on the target screen.
        let clampedX = min(max(visible.midX - size.width / 2, visible.minX), visible.maxX - size.width)
        let clampedY = min(max(originY, visible.minY), visible.maxY - size.height)
        let origin = NSPoint(x: clampedX, y: clampedY)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        anchorTop = origin.y + size.height
    }
}

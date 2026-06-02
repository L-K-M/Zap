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
    private let preferences: Preferences
    private var window: NSWindow
    private var hostingView: OverlayHostingView
    private var windowCreatedAt = Date()

    /// Borderless transparent windows can occasionally stop drawing after long
    /// compositor uptime / activation-policy churn. Recycle while hidden so the
    /// next presentation starts from a fresh WindowServer/SwiftUI host.
    private let maximumWindowAge: TimeInterval = 30 * 60

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
        self.preferences = preferences
        let created = Self.makeWindow(model: model, preferences: preferences)
        window = created.window
        hostingView = created.hostingView
    }

    private static func makeWindow(model: OverlayModel, preferences: Preferences) -> (window: NSWindow, hostingView: OverlayHostingView) {
        let hostingView = OverlayHostingView(rootView: OverlayView(model: model, preferences: preferences))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .popUpMenu
        window.canHide = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        window.isRestorable = false
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
        return (window, hostingView)
    }

    // MARK: Presentation

    func show(apps: [AppInfo], selectedIndex: Int, on screen: NSScreen) {
        refreshWindowIfNeeded()
        resetWindowPresentationState()

        model.apps = apps
        model.selectedIndex = selectedIndex
        model.quittingPIDs = []
        model.windows = []
        model.windowSelectedIndex = nil
        model.windowThumbnails = [:]

        currentScreen = screen
        // Reassigning the root view is cheap (the model stays the same) and nudges
        // SwiftUI/AppKit to rebuild a host that may have stopped drawing while idle.
        hostingView.rootView = OverlayView(model: model, preferences: preferences)
        layout(keepTop: false)
        window.orderFrontRegardless()
        forceDisplay()
        isVisible = true
    }

    func updateSelection(_ index: Int) {
        model.selectedIndex = index
    }

    /// Updates which app icons render dimmed (pending-quit) and moves the
    /// highlight, without resizing or repositioning the panel.
    func setQuitting(_ pids: Set<pid_t>, selectedIndex: Int) {
        model.quittingPIDs = pids
        model.selectedIndex = selectedIndex
    }

    /// Replaces the app row (e.g. once a quit is confirmed and the icon is
    /// dropped), keeping the panel's top edge fixed so the row doesn't jump.
    func updateApps(_ apps: [AppInfo], selectedIndex: Int, quitting: Set<pid_t>) {
        model.apps = apps
        model.selectedIndex = selectedIndex
        model.quittingPIDs = quitting
        model.windows = []
        model.windowSelectedIndex = nil
        model.windowThumbnails = [:]
        layout(keepTop: true)
        forceDisplay()
    }

    // MARK: Window list

    /// Replaces the window list and re-lays-out the panel keeping its top fixed.
    func setWindows(_ windows: [WindowInfo], selected: Int?) {
        model.windows = windows
        model.windowSelectedIndex = selected
        model.windowThumbnails = [:]
        layout(keepTop: true)
        forceDisplay()
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
        forceDisplay()
    }

    func hide() {
        guard isVisible else { return }
        window.orderOut(nil)
        isVisible = false
        model.apps = []
        model.selectedIndex = 0
        model.quittingPIDs = []
        model.windows = []
        model.windowSelectedIndex = nil
        model.windowThumbnails = [:]
        anchorTop = nil
        currentScreen = nil
    }

    private func refreshWindowIfNeeded() {
        let agedOut = Date().timeIntervalSince(windowCreatedAt) > maximumWindowAge
        let disconnected = window.contentView == nil || hostingView.window !== window
        guard !isVisible, agedOut || disconnected else { return }
        NSLog("Zap: recycling overlay window (agedOut: \(agedOut), disconnected: \(disconnected))")
        window.orderOut(nil)
        let created = Self.makeWindow(model: model, preferences: preferences)
        window = created.window
        hostingView = created.hostingView
        windowCreatedAt = Date()
    }

    private func resetWindowPresentationState() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 1
        window.level = .popUpMenu
        window.canHide = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.contentView?.isHidden = false
        hostingView.isHidden = false
        hostingView.alphaValue = 1
    }

    private func forceDisplay() {
        hostingView.needsLayout = true
        hostingView.needsDisplay = true
        window.contentView?.needsDisplay = true
        window.displayIfNeeded()
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
            width: min(max(safeDimension(fitting.width, fallback: 80), 80), visible.width - horizontalMargin),
            height: min(max(safeDimension(fitting.height, fallback: 80), 80), visible.height)
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
        hostingView.frame = window.contentView?.bounds ?? NSRect(origin: .zero, size: size)
        anchorTop = origin.y + size.height
    }

    private func safeDimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : fallback
    }
}

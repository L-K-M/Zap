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

    /// A pending corrective re-layout. A freshly-created or just-reassigned SwiftUI
    /// host can momentarily report a zero/degenerate `fittingSize` before it
    /// reconciles; committing that would clamp the panel to its 80×80 minimum — the
    /// "small square" glitch. We defer sizing (and revealing) until a real size is
    /// available, bounded by `maxLayoutRetries` so a host that never measures still
    /// shows something rather than looping forever.
    private var layoutRetryWorkItem: DispatchWorkItem?
    private var layoutRetryCount = 0
    private let maxLayoutRetries = 10

    /// Local monitor that turns scroll-wheel / trackpad input over the overlay into
    /// row scrolling, plus the sub-icon remainder it carries between events.
    private var scrollMonitor: Any?
    private var scrollAccumulator: CGFloat = 0

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
        installScrollMonitor()
    }

    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
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
        model.scrollAnchorIndex = selectedIndex
        model.quittingPIDs = []
        model.windows = []
        model.windowSelectedIndex = nil
        model.windowThumbnails = [:]

        currentScreen = screen
        // Reassigning the root view is cheap (the model stays the same) and nudges
        // SwiftUI/AppKit to rebuild a host that may have stopped drawing while idle.
        hostingView.rootView = OverlayView(model: model, preferences: preferences)
        // Size first, reveal second. If the host can't be measured yet, `layout`
        // returns false and schedules a retry that reveals the window once it can be
        // sized correctly — so we never flash the 80×80 "small square".
        if layout(keepTop: false) {
            window.orderFrontRegardless()
            forceDisplay()
        }
        isVisible = true
    }

    /// Moves the highlight via keyboard navigation, which also re-anchors the scroll
    /// so the selection is brought into view and centred.
    func updateSelection(_ index: Int) {
        model.selectedIndex = index
        model.scrollAnchorIndex = index
    }

    /// Moves the highlight to follow the pointer. Deliberately leaves the scroll
    /// anchor put: hovering should not scroll the row (that would slide icons out
    /// from under the cursor and make the middle ones unclickable).
    func updateHover(_ index: Int) {
        model.selectedIndex = index
    }

    /// Updates which app icons render dimmed (pending-quit) and moves the
    /// highlight, without resizing or repositioning the panel.
    func setQuitting(_ pids: Set<pid_t>, selectedIndex: Int) {
        model.quittingPIDs = pids
        model.selectedIndex = selectedIndex
        model.scrollAnchorIndex = selectedIndex
    }

    /// Replaces the app row (e.g. once a quit is confirmed and the icon is
    /// dropped), keeping the panel's top edge fixed so the row doesn't jump.
    func updateApps(_ apps: [AppInfo], selectedIndex: Int, quitting: Set<pid_t>) {
        model.apps = apps
        model.selectedIndex = selectedIndex
        model.scrollAnchorIndex = selectedIndex
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
        cancelLayoutRetry()
        scrollAccumulator = 0
        window.orderOut(nil)
        isVisible = false
        model.apps = []
        model.selectedIndex = 0
        model.scrollAnchorIndex = 0
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

    // MARK: Scrolling

    /// Watches for scroll-wheel / trackpad input over the overlay and translates it
    /// into row scrolling. A local monitor sees the event before the inner SwiftUI
    /// `ScrollView` (which a vertical mouse wheel wouldn't drive anyway), so we can
    /// move the keyboard-style scroll anchor — taking the auto-scroll and edge fade
    /// with it — and consume the event so nothing scrolls the row twice.
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isVisible, event.window === self.window else { return event }
            return self.handleScroll(event) ? nil : event
        }
    }

    /// Advances the scroll anchor by however many whole icons the gesture covers.
    /// Returns whether the scroll was consumed (only when the row actually overflows).
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        let count = model.apps.count
        guard count > 1 else { return false }

        // Only scroll when the row is wider than the panel — matches the overlay's
        // own overflow/scroll condition (`maxRowWidth > maxContentWidth`).
        let cellWidth = preferences.iconSize + 16
        let spacing: CGFloat = 12 // matches OverlayView.iconSpacing
        let contentWidth = CGFloat(count) * cellWidth + CGFloat(count - 1) * spacing
        guard contentWidth > model.maxContentWidth else { return false }

        // Trackpad swipes are horizontal and per-pixel; a mouse wheel is vertical and
        // per-line. Take the dominant axis and normalise so a notch ≈ one icon.
        let raw = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        let pointsPerIcon: CGFloat = event.hasPreciseScrollingDeltas ? 60 : 1
        let step = ScrollWheelStepper.steps(raw: raw, pointsPerIcon: pointsPerIcon,
                                            accumulator: &scrollAccumulator)
        if event.phase == .ended || event.momentumPhase == .ended { scrollAccumulator = 0 }

        if step != 0 {
            let next = min(max(model.scrollAnchorIndex + step, 0), count - 1)
            if next != model.scrollAnchorIndex { model.scrollAnchorIndex = next }
        }
        return true
    }

    // MARK: Layout

    /// Sizes and positions the window to fit its SwiftUI content. Returns whether a
    /// real size was committed; `false` means the host wasn't ready to be measured
    /// and a corrective re-layout was scheduled (so the caller should not reveal the
    /// window yet).
    @discardableResult
    private func layout(keepTop: Bool) -> Bool {
        guard let screen = currentScreen else { return false }
        let visible = screen.visibleFrame

        // Cap how wide the icon row may grow before it scrolls. Leave a margin so
        // the panel never butts against the screen edges, and reserve room for the
        // panel's own outer padding — otherwise a crowded row only starts scrolling
        // after the padded panel has already overflowed, clipping the last icons at
        // the screen edge.
        let horizontalMargin: CGFloat = 40
        let maxPanelWidth = visible.width - horizontalMargin
        model.maxContentWidth = max(120, maxPanelWidth - preferences.contentPadding * 2)

        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize

        // A just-created or just-reassigned SwiftUI host can momentarily report a
        // zero/degenerate fitting size before it reconciles. Committing it would
        // clamp the panel to its 80×80 minimum — the "small square" — so defer to
        // the next runloop turn, by which point the host has laid out, instead of
        // stamping that size. Give up after `maxLayoutRetries` so a host that never
        // measures still shows something.
        let measured = fitting.width.isFinite && fitting.width > 1
            && fitting.height.isFinite && fitting.height > 1
        guard measured || layoutRetryCount >= maxLayoutRetries else {
            scheduleLayoutRetry(keepTop: keepTop)
            return false
        }
        cancelLayoutRetry()

        let size = NSSize(
            width: min(max(safeDimension(fitting.width, fallback: 80), 80), maxPanelWidth),
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
        return true
    }

    /// Schedules a corrective re-layout one frame later, after the SwiftUI host has
    /// had a runloop turn to reconcile and report a real fitting size. If this is
    /// the initial presentation (the window isn't on screen yet), revealing it is
    /// deferred to this retry so the panel only ever appears at its correct size.
    private func scheduleLayoutRetry(keepTop: Bool) {
        layoutRetryCount += 1
        layoutRetryWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.layoutRetryWorkItem = nil
            guard self.isVisible, self.layout(keepTop: keepTop) else { return }
            if !self.window.isVisible {
                self.window.orderFrontRegardless()
            }
            self.forceDisplay()
        }
        layoutRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0, execute: work)
    }

    private func cancelLayoutRetry() {
        layoutRetryWorkItem?.cancel()
        layoutRetryWorkItem = nil
        layoutRetryCount = 0
    }

    private func safeDimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite && value > 0 ? value : fallback
    }
}

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
    /// continuous row scrolling.
    private var scrollMonitor: Any?

    /// Monitors (local + global) that dismiss the overlay when the user clicks
    /// outside it, when `preferences.closeOnClickOutside` is on.
    private var clickOutsideMonitors: [Any] = []

    /// Extra windows mirroring the panel onto the other screens, when
    /// `preferences.showOnAllScreens` is on. They host the same `model`, so they
    /// render identically and stay interactive (clicks/hover/drops work on any of
    /// them). Empty otherwise — leaving the single-screen path untouched.
    private var mirrorWindows: [NSWindow] = []

    /// Invoked when the user clicks outside the panel (and the setting is enabled).
    var onClickOutside: (() -> Void)?

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

    /// Invoked when files are dropped on an app icon. Arguments: index and file URLs.
    var onDropFiles: ((Int, [URL]) -> Void)? {
        get { model.onDropFiles }
        set { model.onDropFiles = newValue }
    }

    init(preferences: Preferences) {
        self.preferences = preferences
        let created = Self.makeWindow(model: model, preferences: preferences)
        window = created.window
        hostingView = created.hostingView
        installScrollMonitor()
        installClickOutsideMonitor()
    }

    deinit {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        clickOutsideMonitors.forEach { NSEvent.removeMonitor($0) }
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
        model.dropTargetIndex = nil

        currentScreen = screen
        // Reassigning the root view is cheap (the model stays the same) and nudges
        // SwiftUI/AppKit to rebuild a host that may have stopped drawing while idle.
        hostingView.rootView = OverlayView(model: model, preferences: preferences)
        // Size first, reveal second. If the host can't be measured yet, `layout`
        // returns false and schedules a retry that reveals the window once it can be
        // sized correctly — so we never flash the 80×80 "small square".
        let committed = layout(keepTop: false)
        // `layout` has set `maxContentWidth`, so the scroll geometry is now known:
        // centre the initial selection before the first frame is shown.
        scrollToCenter(on: selectedIndex, animated: false)
        isVisible = true
        if committed {
            window.orderFrontRegardless()
            forceDisplay()
            syncMirrors()
        }
    }

    /// Moves the highlight via keyboard navigation, which also scrolls to bring the
    /// selection into view, centred.
    func updateSelection(_ index: Int) {
        model.selectedIndex = index
        scrollToCenter(on: index, animated: true)
    }

    /// Moves the highlight to follow the pointer. Deliberately leaves the scroll
    /// position put: hovering should not scroll the row (that would slide icons out
    /// from under the cursor and make the middle ones unclickable).
    func updateHover(_ index: Int) {
        model.selectedIndex = index
    }

    /// Updates which app icons render dimmed (pending-quit) and moves the
    /// highlight, without resizing or repositioning the panel.
    func setQuitting(_ pids: Set<pid_t>, selectedIndex: Int) {
        model.quittingPIDs = pids
        model.selectedIndex = selectedIndex
        scrollToCenter(on: selectedIndex, animated: false)
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
        scrollToCenter(on: selectedIndex, animated: false)
        forceDisplay()
        syncMirrors()
    }

    // MARK: Window list

    /// Replaces the window list and re-lays-out the panel keeping its top fixed.
    func setWindows(_ windows: [WindowInfo], selected: Int?) {
        model.windows = windows
        model.windowSelectedIndex = selected
        model.windowThumbnails = [:]
        layout(keepTop: true)
        forceDisplay()
        syncMirrors()
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
        syncMirrors()
    }

    func hide() {
        guard isVisible else { return }
        cancelLayoutRetry()
        teardownMirrors()
        window.orderOut(nil)
        isVisible = false
        model.apps = []
        model.selectedIndex = 0
        model.dropTargetIndex = nil
        model.scrollOffset = 0
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

    /// Geometry of the icon row, mirroring `OverlayView`: the viewport is the row's
    /// natural width capped at `maxContentWidth` (which `layout` keeps current).
    private func iconRowGeometry() -> IconRowGeometry {
        let cellWidth = preferences.iconSize + 16
        let spacing: CGFloat = 12 // matches OverlayView.iconSpacing
        let count = model.apps.count
        let contentWidth = count > 0 ? CGFloat(count) * cellWidth + CGFloat(count - 1) * spacing : 0
        return IconRowGeometry(count: count, cellWidth: cellWidth, spacing: spacing,
                               viewport: min(contentWidth, model.maxContentWidth))
    }

    /// Scrolls so `index` is centred (clamped at the ends). Animated for keyboard
    /// cycling; instant for presentation and list changes.
    private func scrollToCenter(on index: Int, animated: Bool) {
        let target = iconRowGeometry().centeredOffset(forIndex: index)
        guard target != model.scrollOffset else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) { model.scrollOffset = target }
        } else {
            model.scrollOffset = target
        }
    }

    /// Watches for scroll-wheel / trackpad input over the overlay and scrolls the row
    /// continuously. A local monitor sees the event before the row would (a vertical
    /// mouse wheel wouldn't drive a horizontal scroller anyway), so we move the offset
    /// directly — taking the edge fade with it — and consume the event.
    private func installScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isVisible, self.isOverlayWindow(event.window) else { return event }
            return self.handleScroll(event) ? nil : event
        }
    }

    /// Moves the scroll offset by the gesture's delta. Returns whether the scroll was
    /// consumed (only when the row actually overflows).
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        let geometry = iconRowGeometry()
        guard geometry.overflows else { return false }

        // Trackpad swipes are horizontal and per-pixel; a mouse wheel is vertical and
        // per-line, so scale lines up to points. Take the dominant axis so both work.
        let raw = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        let pointsPerLine: CGFloat = 16
        let delta = event.hasPreciseScrollingDeltas ? raw : raw * pointsPerLine
        // A downward / leftward gesture advances toward later icons. (Flip the sign
        // here if it feels inverted on your pointer settings.)
        if delta != 0 {
            model.scrollOffset = geometry.clamp(model.scrollOffset - delta)
        }
        return true
    }

    // MARK: Click-outside dismissal

    /// Dismisses the overlay when the user clicks away from it. A global monitor
    /// catches clicks in other apps (always "outside"); a local monitor catches
    /// clicks in Zap's own windows and dismisses only those that miss the panel — so
    /// clicking an icon still selects, and clicking the panel's padding doesn't
    /// dismiss. Neither consumes the click; it proceeds to whatever it landed on.
    private func installClickOutsideMonitor() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.dismissIfClickedOutside()
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if let self, !self.isOverlayWindow(event.window) {
                self.dismissIfClickedOutside()
            }
            return event
        }
        clickOutsideMonitors = [global, local].compactMap { $0 }
    }

    private func dismissIfClickedOutside() {
        guard isVisible, preferences.closeOnClickOutside else { return }
        onClickOutside?()
    }

    // MARK: Mirror windows (show on all screens)

    /// Whether `candidate` is the primary overlay window or one of its mirrors.
    private func isOverlayWindow(_ candidate: NSWindow?) -> Bool {
        guard let candidate else { return false }
        return candidate === window || mirrorWindows.contains { $0 === candidate }
    }

    /// Brings the panel up on the other screens (when `showOnAllScreens` is on), or
    /// tears the mirrors down. Each mirror hosts the same `model`, so it renders and
    /// behaves identically; they're sized to the primary window and placed two-thirds
    /// up their own screen. Idempotent — safe to call after every (re)layout.
    private func syncMirrors() {
        let others: [NSScreen]
        if isVisible, preferences.showOnAllScreens, let primary = currentScreen {
            others = NSScreen.screens.filter { $0 !== primary }
        } else {
            others = []
        }

        // Rebuild only when the set of mirrored screens changes (rare); otherwise
        // just reposition the existing mirrors below.
        if mirrorWindows.count != others.count {
            teardownMirrors()
            mirrorWindows = others.map { _ in Self.makeWindow(model: model, preferences: preferences).window }
        }
        guard !mirrorWindows.isEmpty else { return }

        let size = window.frame.size
        for (mirror, screen) in zip(mirrorWindows, others) {
            let visible = screen.visibleFrame
            let centerY = visible.minY + visible.height * (2.0 / 3.0)
            let originX = min(max(visible.midX - size.width / 2, visible.minX), visible.maxX - size.width)
            let originY = min(max(centerY - size.height / 2, visible.minY), visible.maxY - size.height)
            mirror.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: size), display: true)
            mirror.orderFrontRegardless()
        }
    }

    private func teardownMirrors() {
        mirrorWindows.forEach { $0.orderOut(nil) }
        mirrorWindows.removeAll()
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
            self.syncMirrors()
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

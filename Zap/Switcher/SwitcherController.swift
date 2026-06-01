import AppKit
import Carbon.HIToolbox

/// Coordinates hotkey input, the app list, and the overlay window.
///
/// Two trigger modes:
/// - **Event-tap mode** (preferred): real ⌘+Tab is intercepted; the overlay shows
///   while Command is held and commits on release — matching the native feel.
/// - **Fallback mode**: an alternate Carbon hotkey advances the selection and
///   auto-commits after a short delay (used when Accessibility is denied).
///
/// A *session* begins on the first cycle and ends on commit/cancel. The overlay
/// is shown after `showDelayMs` (so a quick tap-and-release doesn't flash the UI),
/// or immediately once the user cycles a second time.
final class SwitcherController {

    private let preferences: Preferences
    private let provider: AppListProvider
    private let overlay: OverlayWindowController
    private let eventTap = EventTapMonitor()
    private let forwardHotkey = CarbonHotkey(identifier: 1)
    private let reverseHotkey = CarbonHotkey(identifier: 2)

    private var apps: [AppInfo] = []
    private var selectedIndex = 0
    private var isSessionActive = false
    private var usesEventTap = false
    private var isPaused = false

    private var showTimer: Timer?
    private var autoCommitTimer: Timer?

    /// Auto-commit delay used only in fallback mode.
    private let autoCommitInterval: TimeInterval = 0.8

    /// Whether the switcher is currently driven by the real ⌘+Tab event tap.
    var isUsingEventTap: Bool { usesEventTap }

    init(preferences: Preferences) {
        self.preferences = preferences
        self.provider = AppListProvider(preferences: preferences)
        self.overlay = OverlayWindowController(preferences: preferences)
        wireEventTap()
        overlay.onPick = { [weak self] index in self?.pick(index) }
    }

    // MARK: Lifecycle

    /// Starts input monitoring, choosing event-tap or fallback mode.
    func start() {
        if AccessibilityAuthorizer.isTrusted {
            usesEventTap = eventTap.start()
        }
        if !usesEventTap {
            startFallback()
        }
    }

    func pause() {
        isPaused = true
        eventTap.setEnabled(false)
        forwardHotkey.unregister()
        reverseHotkey.unregister()
        cancel()
    }

    func resume() {
        isPaused = false
        if usesEventTap {
            eventTap.setEnabled(true)
        } else {
            startFallback()
        }
    }

    // MARK: Wiring

    private func wireEventTap() {
        eventTap.isSwitching = { [weak self] in self?.isSessionActive ?? false }
        eventTap.onCycle = { [weak self] forward in self?.cycle(forward: forward) }
        eventTap.onCommit = { [weak self] in self?.commit() }
        eventTap.onCancel = { [weak self] in self?.cancel() }
        eventTap.onQuitSelected = { [weak self] in self?.quitSelected() }
    }

    private func startFallback() {
        // ⌥+Tab forward, ⌥+Shift+Tab reverse.
        let option = UInt32(optionKey)
        let shift = UInt32(shiftKey)
        forwardHotkey.onPressed = { [weak self] in self?.fallbackCycle(forward: true) }
        reverseHotkey.onPressed = { [weak self] in self?.fallbackCycle(forward: false) }
        forwardHotkey.register(keyCode: KeyCode.Carbon.tab, modifiers: option)
        reverseHotkey.register(keyCode: KeyCode.Carbon.tab, modifiers: option | shift)
    }

    // MARK: Cycling

    private func cycle(forward: Bool) {
        guard !isPaused else { return }
        if isSessionActive {
            advanceSelection(forward: forward)
        } else {
            beginSession(forward: forward)
        }
    }

    private func fallbackCycle(forward: Bool) {
        cycle(forward: forward)
        // Without modifier-release detection, commit after a brief pause.
        scheduleAutoCommit()
    }

    private func beginSession(forward: Bool) {
        apps = provider.currentApps()
        guard !apps.isEmpty else { return }

        // Pre-select the previous app (index 1) so a single press toggles the
        // two most-recent apps, like the native switcher.
        selectedIndex = forward ? (apps.count > 1 ? 1 : 0) : apps.count - 1
        isSessionActive = true

        let delay = max(0, preferences.showDelayMs / 1000)
        if delay == 0 {
            presentOverlay()
        } else {
            showTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.presentOverlay()
            }
        }
    }

    private func advanceSelection(forward: Bool) {
        guard !apps.isEmpty else { return }
        let count = apps.count
        selectedIndex = ((selectedIndex + (forward ? 1 : -1)) % count + count) % count

        if overlay.isVisible {
            overlay.updateSelection(selectedIndex)
        } else {
            // User is actively cycling — show the overlay now instead of waiting.
            presentOverlay()
        }
    }

    private func presentOverlay() {
        showTimer?.invalidate()
        showTimer = nil
        guard isSessionActive, !apps.isEmpty, let screen = targetScreen() else { return }
        overlay.show(apps: apps, selectedIndex: selectedIndex, on: screen)
    }

    // MARK: Commit / cancel

    private func commit() {
        let target = isSessionActive && apps.indices.contains(selectedIndex) ? apps[selectedIndex] : nil
        endSession()
        if let target {
            activate(target)
        }
    }

    private func cancel() {
        endSession()
    }

    /// Handles a click on an app icon: select it and switch immediately.
    private func pick(_ index: Int) {
        guard isSessionActive, apps.indices.contains(index) else { return }
        selectedIndex = index
        commit()
    }

    private func endSession() {
        showTimer?.invalidate(); showTimer = nil
        autoCommitTimer?.invalidate(); autoCommitTimer = nil
        isSessionActive = false
        overlay.hide()
    }

    private func quitSelected() {
        guard isSessionActive, apps.indices.contains(selectedIndex) else { return }
        provider.runningApplication(for: apps[selectedIndex])?.terminate()

        apps = provider.currentApps()
        guard !apps.isEmpty else {
            cancel()
            return
        }
        selectedIndex = min(selectedIndex, apps.count - 1)
        if overlay.isVisible, let screen = targetScreen() {
            overlay.show(apps: apps, selectedIndex: selectedIndex, on: screen)
        }
    }

    private func scheduleAutoCommit() {
        autoCommitTimer?.invalidate()
        autoCommitTimer = Timer.scheduledTimer(withTimeInterval: autoCommitInterval, repeats: false) { [weak self] _ in
            self?.commit()
        }
    }

    // MARK: Helpers

    private func activate(_ info: AppInfo) {
        guard let app = provider.runningApplication(for: info) else { return }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

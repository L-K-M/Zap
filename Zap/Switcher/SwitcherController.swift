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

    private var windows: [WindowInfo] = []
    private var windowSelectedIndex: Int?

    private var showTimer: Timer?
    private var autoCommitTimer: Timer?
    private var dwellTimer: Timer?

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
        overlay.onHoverApp = { [weak self] index in self?.hoverApp(index) }
        overlay.onPickWindow = { [weak self] index in self?.pickWindow(index) }
        overlay.onHoverWindow = { [weak self] index in self?.hoverWindow(index) }
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
        eventTap.onCloseWindow = { [weak self] in self?.closeFocusedWindow() }
        eventTap.onNavigateWindows = { [weak self] down in self?.navigateWindows(down: down) }
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
            restartDwell()
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
        restartDwell()
    }

    // MARK: Commit / cancel

    private func commit() {
        let targetApp = isSessionActive && apps.indices.contains(selectedIndex) ? apps[selectedIndex] : nil
        let targetWindow: WindowInfo? = {
            guard let index = windowSelectedIndex, windows.indices.contains(index) else { return nil }
            return windows[index]
        }()
        endSession()
        if let targetWindow, let targetApp {
            WindowEnumerator.raise(targetWindow, pid: targetApp.processIdentifier)
        } else if let targetApp {
            activate(targetApp)
        }
    }

    private func cancel() {
        endSession()
    }

    /// Handles a click on an app icon: select it and switch immediately.
    private func pick(_ index: Int) {
        guard isSessionActive, apps.indices.contains(index) else { return }
        selectedIndex = index
        windowSelectedIndex = nil
        commit()
    }

    private func endSession() {
        showTimer?.invalidate(); showTimer = nil
        autoCommitTimer?.invalidate(); autoCommitTimer = nil
        dwellTimer?.invalidate(); dwellTimer = nil
        isSessionActive = false
        windows = []
        windowSelectedIndex = nil
        overlay.hide()
    }

    private func quitSelected() {
        guard isSessionActive, apps.indices.contains(selectedIndex) else { return }
        let victim = apps[selectedIndex]

        // The Finder can't meaningfully be quit — it relaunches immediately — so
        // leave it in place rather than terminating it and dropping it from the
        // list only to have it reappear.
        guard victim.bundleIdentifier != "com.apple.finder" else { return }

        provider.runningApplication(for: victim)?.terminate()

        // `terminate()` is asynchronous, so the app can still appear in the live
        // running list for a moment. Drop it explicitly so the overlay updates
        // right away and a later commit (on ⌘ release) doesn't re-activate — and
        // thereby cancel the quit of — the app we just asked to quit.
        apps = provider.currentApps().filter { $0.processIdentifier != victim.processIdentifier }
        windows = []
        windowSelectedIndex = nil
        guard !apps.isEmpty else {
            cancel()
            return
        }
        selectedIndex = min(selectedIndex, apps.count - 1)
        if overlay.isVisible, let screen = targetScreen() {
            overlay.show(apps: apps, selectedIndex: selectedIndex, on: screen)
            restartDwell()
        }
    }

    // MARK: Hover

    /// Moves the selection to the hovered app and restarts the dwell timer so its
    /// windows reveal after the configured delay.
    private func hoverApp(_ index: Int) {
        guard isSessionActive, apps.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        overlay.updateSelection(index)
        restartDwell()
    }

    private func hoverWindow(_ index: Int) {
        guard windows.indices.contains(index) else { return }
        windowSelectedIndex = index
        overlay.updateWindowSelection(index)
    }

    // MARK: Window list

    /// (Re)starts the dwell timer that reveals the selected app's windows. Clears
    /// any currently-shown window list first.
    private func restartDwell() {
        dwellTimer?.invalidate(); dwellTimer = nil
        clearWindows()
        guard
            preferences.showWindowList,
            AccessibilityAuthorizer.isTrusted,
            overlay.isVisible
        else { return }

        let interval = max(0.1, preferences.windowDwellMs / 1000)
        dwellTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.revealWindows()
        }
    }

    private func clearWindows() {
        guard !windows.isEmpty else { return }
        windows = []
        windowSelectedIndex = nil
        overlay.clearWindows()
    }

    /// Enumerates the selected app's windows and reveals the list when it has at
    /// least two windows worth choosing between.
    private func revealWindows() {
        guard isSessionActive, overlay.isVisible, apps.indices.contains(selectedIndex) else { return }
        let found = WindowEnumerator.windows(forPID: apps[selectedIndex].processIdentifier)
        guard found.count >= 2 else { return }
        windows = found
        windowSelectedIndex = nil
        overlay.setWindows(found, selected: nil)
    }

    /// Moves through the revealed window list. Down advances; Up moves back and,
    /// from the first window, returns focus to the app row.
    private func navigateWindows(down: Bool) {
        guard !windows.isEmpty else { return }
        let count = windows.count
        if down {
            let next = (windowSelectedIndex ?? -1) + 1
            windowSelectedIndex = min(next, count - 1)
        } else if let current = windowSelectedIndex {
            windowSelectedIndex = current == 0 ? nil : current - 1
        } else {
            windowSelectedIndex = nil
        }
        overlay.updateWindowSelection(windowSelectedIndex)
    }

    /// Handles a click on a window row: select it and switch immediately.
    private func pickWindow(_ index: Int) {
        guard isSessionActive, windows.indices.contains(index) else { return }
        windowSelectedIndex = index
        commit()
    }

    /// Closes the focused window (⌘W in the window list) and keeps the list in
    /// sync, advancing the highlight to the next remaining window.
    private func closeFocusedWindow() {
        guard
            isSessionActive,
            let index = windowSelectedIndex,
            windows.indices.contains(index)
        else { return }

        WindowEnumerator.close(windows[index])
        windows.remove(at: index)

        if windows.isEmpty {
            windowSelectedIndex = nil
            overlay.clearWindows()
        } else {
            windowSelectedIndex = min(index, windows.count - 1)
            overlay.setWindows(windows, selected: windowSelectedIndex)
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
        // `.activateAllWindows` raises every window of the app, not just its main
        // one — so switching to the already-frontmost app still brings all of its
        // windows forward (matching the native switcher).
        app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

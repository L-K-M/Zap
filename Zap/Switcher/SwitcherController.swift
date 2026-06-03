import AppKit
import Carbon.HIToolbox
import Combine

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

    /// Reports the live trigger mode to the Settings UI.
    let inputMode = InputModeReporter()
    private var cancellables: Set<AnyCancellable> = []

    private var windows: [WindowInfo] = []
    private var windowSelectedIndex: Int?

    /// Captures window previews off the hot path. A monotonically-increasing
    /// generation token lets late async captures bail when the window list has
    /// since changed or closed.
    private let thumbnails = WindowThumbnailProvider()
    private var windowsGeneration = 0

    private var showTimer: Timer?
    private var autoCommitTimer: Timer?
    private var dwellTimer: Timer?

    /// Auto-commit delay used only in fallback mode.
    private let autoCommitInterval: TimeInterval = 0.8

    /// Apps we asked to quit and are still verifying, keyed by process id. The
    /// app stays in `apps` (shown dimmed, skipped by the selection) until we know
    /// whether it terminated — then it's dropped — or refused, then restored.
    private var pendingQuits: [pid_t: PendingQuit] = [:]

    /// The subset of `apps` currently shown dimmed as pending-quit. Mirrors
    /// `pendingQuits.keys` but kept as a `Set` for cheap membership checks on the
    /// selection hot path; pushed to the overlay so it can dim those icons.
    private var quittingPIDs: Set<pid_t> = []

    /// How long to wait after asking an app to quit before deciding it refused.
    /// Long enough that a normal (even slow) quit completes first, short enough
    /// that a stuck app un-dims while the user may still be holding ⌘.
    private let quitVerificationDelay: TimeInterval = 2

    /// An app the user asked to quit that we're verifying.
    private struct PendingQuit {
        let runningApp: NSRunningApplication
        let timer: Timer
    }

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
        // A click outside the panel dismisses the session (when the user enables it).
        overlay.onClickOutside = { [weak self] in self?.cancel() }
        overlay.onDropFiles = { [weak self] index, urls in self?.openFiles(urls, withAppAt: index) }

        // Reconfigure live if the user toggles the alternate-hotkey preference.
        preferences.$useAlternateHotkey
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.applyInputMode() }
            .store(in: &cancellables)

        // Free cached previews when the user turns the feature off.
        preferences.$showWindowPreviews
            .dropFirst()
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in
                guard let self else { return }
                Task { [thumbnails = self.thumbnails] in await thumbnails.clear() }
            }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    /// Starts input monitoring, choosing event-tap or fallback mode.
    func start() {
        applyInputMode()
    }

    /// (Re)configures the active trigger based on permission state and the
    /// `useAlternateHotkey` preference. Safe to call repeatedly.
    private func applyInputMode() {
        guard !isPaused else { return }

        // Tear down whatever is currently installed so we start clean.
        eventTap.setEnabled(false)
        forwardHotkey.unregister()
        reverseHotkey.unregister()
        usesEventTap = false

        // The preference forces the ⌥+Tab fallback even when ⌘+Tab is available.
        let forceFallback = preferences.useAlternateHotkey

        if !forceFallback && AccessibilityAuthorizer.isTrusted {
            usesEventTap = eventTap.start()
            if usesEventTap {
                eventTap.setEnabled(true)
                inputMode.update(.eventTap)
                return
            }
        }

        // Fall back to the Carbon hotkey.
        let registered = startFallback()
        inputMode.update(registered ? .fallback : .unavailable)
    }

    func pause() {
        isPaused = true
        eventTap.setEnabled(false)
        forwardHotkey.unregister()
        reverseHotkey.unregister()
        cancel()
        inputMode.update(.paused)
    }

    func resume() {
        isPaused = false
        // Re-evaluate from scratch: if Accessibility was granted while paused (or
        // since launch), this promotes us from fallback to the real event tap.
        applyInputMode()
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

    @discardableResult
    private func startFallback() -> Bool {
        // ⌥+Tab forward, ⌥+Shift+Tab reverse.
        let option = UInt32(optionKey)
        let shift = UInt32(shiftKey)
        forwardHotkey.onPressed = { [weak self] in self?.fallbackCycle(forward: true) }
        reverseHotkey.onPressed = { [weak self] in self?.fallbackCycle(forward: false) }
        let forwardOK = forwardHotkey.register(keyCode: KeyCode.Carbon.tab, modifiers: option)
        let reverseOK = reverseHotkey.register(keyCode: KeyCode.Carbon.tab, modifiers: option | shift)
        if !(forwardOK && reverseOK) {
            NSLog("Zap: alternate hotkey registration failed (forward: \(forwardOK), reverse: \(reverseOK))")
        }
        // Forward cycling is the essential capability; treat that as "fallback active".
        return forwardOK
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

        // Pre-select the previous app so a single press toggles the two
        // most-recent apps, like the native switcher. Normally that's index 1,
        // but if the frontmost app was excluded (and thus filtered out), index 0
        // already *is* the previous visible app — selecting index 1 would skip it.
        selectedIndex = defaultSelection(forward: forward, apps: apps,
                                         frontmostBundleID: provider.frontmostBundleID())
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

    /// Pure helper computing the initial highlighted index for a new session.
    ///
    /// Forward: highlight the previous app (index 1) so a tap toggles the two
    /// MRU apps — but if the frontmost app didn't survive filtering (it's
    /// excluded), index 0 is already the previous app, so highlight it instead.
    /// Reverse: highlight the least-recently-used app (last index).
    static func defaultSelection(forward: Bool, apps: [AppInfo], frontmostBundleID: String?) -> Int {
        guard !apps.isEmpty else { return 0 }
        guard forward else { return apps.count - 1 }
        guard apps.count > 1 else { return 0 }
        let frontmostSurvived = frontmostBundleID != nil
            && apps.first?.bundleIdentifier == frontmostBundleID
        return frontmostSurvived ? 1 : 0
    }

    private func defaultSelection(forward: Bool, apps: [AppInfo], frontmostBundleID: String?) -> Int {
        Self.defaultSelection(forward: forward, apps: apps, frontmostBundleID: frontmostBundleID)
    }

    private func advanceSelection(forward: Bool) {
        guard let next = nextSelectableIndex(from: selectedIndex, forward: forward) else { return }
        selectedIndex = next

        if overlay.isVisible {
            overlay.updateSelection(selectedIndex)
            restartDwell()
        } else {
            // User is actively cycling — show the overlay now instead of waiting.
            presentOverlay()
        }
    }

    /// The next index in `direction` that isn't a dimmed pending-quit app, so the
    /// highlight skips over apps on their way out. Wraps around; returns `nil`
    /// only when there's no selectable app (empty, or every app is quitting).
    private func nextSelectableIndex(from index: Int, forward: Bool) -> Int? {
        guard !apps.isEmpty else { return nil }
        let count = apps.count
        let step = forward ? 1 : -1
        for offset in 1...count {
            let candidate = ((index + step * offset) % count + count) % count
            if !quittingPIDs.contains(apps[candidate].processIdentifier) {
                return candidate
            }
        }
        return nil
    }

    private func presentOverlay() {
        showTimer?.invalidate()
        showTimer = nil
        guard isSessionActive, !apps.isEmpty, let screen = targetScreen() else { return }
        overlay.show(apps: apps, selectedIndex: selectedIndex, on: screen)
        // `show` clears the dim state; re-apply it in case a quit was requested
        // before the overlay first appeared.
        if !quittingPIDs.isEmpty {
            overlay.setQuitting(quittingPIDs, selectedIndex: selectedIndex)
        }
        restartDwell()
    }

    // MARK: Commit / cancel

    private func commit() {
        // Never activate an app that's on its way out (selection normally skips
        // these, but guard in case it's the last one standing).
        let targetApp: AppInfo? = {
            guard isSessionActive, apps.indices.contains(selectedIndex) else { return nil }
            let app = apps[selectedIndex]
            return quittingPIDs.contains(app.processIdentifier) ? nil : app
        }()
        let targetWindow: WindowInfo? = {
            guard let index = windowSelectedIndex, windows.indices.contains(index) else { return nil }
            return windows[index]
        }()
        endSession()
        if let targetWindow, let targetApp {
            DispatchQueue.main.async {
                WindowEnumerator.raise(targetWindow, pid: targetApp.processIdentifier)
            }
        } else if let targetApp {
            DispatchQueue.main.async { [weak self] in
                self?.activate(targetApp)
            }
        }
    }

    private func cancel() {
        endSession()
    }

    /// Handles a click on an app icon: select it and switch immediately.
    private func pick(_ index: Int) {
        guard isSessionActive, apps.indices.contains(index) else { return }
        // Ignore clicks on a dimmed app that's quitting.
        guard !quittingPIDs.contains(apps[index].processIdentifier) else { return }
        selectedIndex = index
        windowSelectedIndex = nil
        commit()
    }

    /// Handles files dropped on an app icon: open them with that app (activating it),
    /// then dismiss — like dropping onto an app in the Dock.
    private func openFiles(_ urls: [URL], withAppAt index: Int) {
        guard isSessionActive, apps.indices.contains(index) else { return }
        let target = apps[index]
        // Don't hand files to an app that's on its way out.
        guard !quittingPIDs.contains(target.processIdentifier) else { return }
        endSession()

        guard !urls.isEmpty,
              let runningApp = provider.runningApplication(for: target),
              let appURL = runningApp.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Zap: failed to open \(urls.count) file(s) with \(target.bundleIdentifier): \(error.localizedDescription)")
            }
        }
    }

    private func endSession() {
        showTimer?.invalidate(); showTimer = nil
        autoCommitTimer?.invalidate(); autoCommitTimer = nil
        dwellTimer?.invalidate(); dwellTimer = nil
        isSessionActive = false
        quittingPIDs.removeAll()
        windows = []
        windowSelectedIndex = nil
        windowsGeneration &+= 1
        overlay.hide()
    }

    private func quitSelected() {
        guard isSessionActive, apps.indices.contains(selectedIndex) else { return }
        let victim = apps[selectedIndex]

        // The Finder can't meaningfully be quit — it relaunches immediately — so
        // leave it in place rather than terminating it and dropping it.
        guard victim.bundleIdentifier != "com.apple.finder" else { return }

        let pid = victim.processIdentifier
        guard !quittingPIDs.contains(pid) else { return }     // already on its way out

        // `terminate()` only *requests* a polite quit (so the app can prompt about
        // unsaved changes); it can keep running. Resolve the live process first so
        // we can later check whether it actually went away.
        guard let runningApp = provider.runningApplication(for: victim) else { return }
        runningApp.terminate()
        quittingPIDs.insert(pid)
        scheduleQuitVerification(for: runningApp)

        // Don't yank the app out yet — dim it and jump the highlight to the next
        // live app. The icon is removed (or restored) once `verifyQuit` knows
        // whether the quit took. A commit while it's dimmed won't re-activate it.
        if let next = nextSelectableIndex(from: selectedIndex, forward: true) {
            selectedIndex = next
        }
        windows = []
        windowSelectedIndex = nil
        windowsGeneration &+= 1
        overlay.setQuitting(quittingPIDs, selectedIndex: selectedIndex)
        overlay.clearWindows()
        restartDwell()
    }

    /// Starts the one-shot timer that checks whether `runningApp` actually quit.
    private func scheduleQuitVerification(for runningApp: NSRunningApplication) {
        let pid = runningApp.processIdentifier
        pendingQuits[pid]?.timer.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: quitVerificationDelay, repeats: false) { [weak self] _ in
            self?.verifyQuit(pid: pid)
        }
        pendingQuits[pid] = PendingQuit(runningApp: runningApp, timer: timer)
    }

    /// Resolves a pending quit: if the app terminated, drop its (dimmed) icon for
    /// good; if it refused — typically a save/confirm dialog keeps it alive —
    /// restore it to full opacity so it can be chosen again.
    private func verifyQuit(pid: pid_t) {
        guard let pending = pendingQuits.removeValue(forKey: pid) else { return }
        let terminated = pending.runningApp.isTerminated
        quittingPIDs.remove(pid)

        // With no session on screen there's nothing to update — the next list the
        // switcher builds reflects reality (terminated apps gone, survivors back).
        guard isSessionActive else { return }

        if terminated {
            removeApp(pid: pid)
        } else {
            overlay.setQuitting(quittingPIDs, selectedIndex: selectedIndex)
        }
    }

    /// Drops a confirmed-quit app from the list, keeping the selection stable, and
    /// re-lays-out the (now narrower) panel.
    private func removeApp(pid: pid_t) {
        guard let index = apps.firstIndex(where: { $0.processIdentifier == pid }) else { return }
        let previousSelection = apps.indices.contains(selectedIndex) ? apps[selectedIndex] : nil
        apps.remove(at: index)
        guard !apps.isEmpty else {
            cancel()
            return
        }
        if let previousSelection, let newIndex = apps.firstIndex(of: previousSelection) {
            selectedIndex = newIndex
        } else {
            selectedIndex = min(selectedIndex, apps.count - 1)
        }
        windows = []
        windowSelectedIndex = nil
        windowsGeneration &+= 1
        overlay.updateApps(apps, selectedIndex: selectedIndex, quitting: quittingPIDs)
        restartDwell()
    }

    // MARK: Hover

    /// Moves the selection to the hovered app and restarts the dwell timer so its
    /// windows reveal after the configured delay.
    private func hoverApp(_ index: Int) {
        guard isSessionActive, apps.indices.contains(index), index != selectedIndex else { return }
        // Don't let the pointer land the highlight on a dimmed, quitting app.
        guard !quittingPIDs.contains(apps[index].processIdentifier) else { return }
        selectedIndex = index
        overlay.updateHover(index)
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
        windowsGeneration &+= 1
        overlay.clearWindows()
    }

    /// Enumerates the selected app's windows and reveals the list when it has at
    /// least two windows worth choosing between.
    private func revealWindows() {
        guard isSessionActive, overlay.isVisible, apps.indices.contains(selectedIndex) else { return }
        // The selection can rest on a quitting app only when it's the last one
        // left; don't reveal windows for an app that's on its way out.
        guard !quittingPIDs.contains(apps[selectedIndex].processIdentifier) else { return }
        let found = WindowEnumerator.windows(forPID: apps[selectedIndex].processIdentifier)
        guard found.count >= 2 else { return }
        windows = found
        windowSelectedIndex = nil
        overlay.setWindows(found, selected: nil)
        loadThumbnails()
    }

    /// Kicks off asynchronous preview capture for the visible windows when the
    /// feature is enabled and Screen Recording is granted. Each capture is applied
    /// on the main actor and discarded if the window list changed meanwhile.
    private func loadThumbnails() {
        guard preferences.showWindowPreviews, ScreenRecordingAuthorizer.isGranted else { return }

        windowsGeneration &+= 1
        let generation = windowsGeneration
        // Minimized/off-screen windows have no backing store to capture.
        let ids = windows.compactMap { $0.isMinimized ? nil : $0.cgWindowID }
        guard !ids.isEmpty else { return }

        let maxDimension = WindowPreviewMetrics.maxDimension
        Task { [weak self, thumbnails = thumbnails] in
            for id in ids {
                guard let image = await thumbnails.thumbnail(for: id, maxDimension: maxDimension) else { continue }
                await self?.applyWindowThumbnail(image, for: id, generation: generation)
            }
        }
    }

    @MainActor
    private func applyWindowThumbnail(_ image: NSImage, for windowID: CGWindowID, generation: Int) {
        guard windowsGeneration == generation else { return }
        overlay.setWindowThumbnail(image, for: windowID)
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

        // Only drop the row if the close actually succeeded; otherwise the window
        // (no close button, denied AX action, …) would vanish from the overlay
        // while staying open on screen.
        guard WindowEnumerator.close(windows[index]) else { return }
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
        guard let app = provider.runningApplication(for: info) else {
            NSLog("Zap: could not resolve running app for \(info.bundleIdentifier)")
            return
        }
        // A hidden app (⌘H) won't reappear from `activate` alone — its windows
        // stay hidden — so explicitly unhide it first.
        if app.isHidden {
            app.unhide()
        }
        // `.activateAllWindows` raises every window of the app, not just its main
        // one — so switching to the already-frontmost app still brings all of its
        // windows forward (matching the native switcher). `WindowEnumerator.activate`
        // yields activation cooperatively so the switch works even after Zap has
        // been the active app (e.g. once Settings has been opened).
        if !WindowEnumerator.activate(app, allWindows: true) {
            NSLog("Zap: failed to activate \(info.bundleIdentifier)")
        }
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

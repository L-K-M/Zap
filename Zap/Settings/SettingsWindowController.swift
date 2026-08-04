import AppKit
import SwiftUI

/// Hosts the SwiftUI `SettingsView` in a standard titled window. Used instead of
/// the SwiftUI `Settings` scene so the agent app can present it on demand on
/// macOS 13+ while remaining an accessory app.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let preferences: Preferences
    private let inputMode: InputModeReporter
    private let updateChecker: UpdateChecker
    private let iconResolver: IconResolver

    private var activationHandoff: ActivationHandoff?

    init(preferences: Preferences, inputMode: InputModeReporter,
         updateChecker: UpdateChecker, iconResolver: IconResolver) {
        self.preferences = preferences
        self.inputMode = inputMode
        self.updateChecker = updateChecker
        self.iconResolver = iconResolver
    }

    func show() {
        // One handoff spans the complete lifetime of this presentation, including
        // time spent hidden or behind another app.
        beginActivationHandoff()

        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(
                preferences: preferences, inputMode: inputMode,
                updateChecker: updateChecker, iconResolver: iconResolver))
            // Only let the SwiftUI content drive the window's *minimum* size; the
            // user is free to make it larger. Without this the hosting controller
            // pins min == max, which both blocks resizing and leaves the fixed-size
            // content padded inside a resizable frame.
            hosting.sizingOptions = [.minSize]

            let window = NSWindow(contentViewController: hosting)
            window.title = "Zap Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 520, height: 460))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            // Set the autosave name last so a previously-saved frame, if any, wins
            // over the centered default position.
            window.setFrameAutosaveName("ZapSettingsWindow")
            self.window = window
        }

        WindowEnumerator.activateSelfForOwnWindow()
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        finishActivationHandoff()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        // A minimized Settings window is no longer a visible Zap destination. End
        // its presentation now rather than leaving Zap active with no UI onscreen.
        finishActivationHandoff()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        // A Dock-driven restore does not pass through `show()`, so begin a fresh
        // presentation here as well. The handoff retains the last external target.
        beginActivationHandoff()
    }

    private func beginActivationHandoff() {
        if activationHandoff == nil { activationHandoff = ActivationHandoff() }
    }

    private func finishActivationHandoff() {
        let handoff = activationHandoff
        activationHandoff = nil
        handoff?.restore()
    }
}

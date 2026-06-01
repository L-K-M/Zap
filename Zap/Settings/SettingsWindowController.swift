import AppKit
import SwiftUI

/// Hosts the SwiftUI `SettingsView` in a standard titled window. Used instead of
/// the SwiftUI `Settings` scene so the agent app can present it on demand on
/// macOS 13+. Restores `.accessory` activation policy when the window closes so
/// the Dock icon disappears again.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let preferences: Preferences
    private let inputMode: InputModeReporter

    init(preferences: Preferences, inputMode: InputModeReporter) {
        self.preferences = preferences
        self.inputMode = inputMode
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(preferences: preferences, inputMode: inputMode))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Zap Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Return to menu-bar-agent behavior (no Dock icon).
        NSApp.setActivationPolicy(.accessory)
    }
}

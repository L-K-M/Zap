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

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Return to menu-bar-agent behavior (no Dock icon).
        NSApp.setActivationPolicy(.accessory)
    }
}

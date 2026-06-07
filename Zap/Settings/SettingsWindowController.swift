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
    private let updateChecker: UpdateChecker

    /// The app that was frontmost when Settings opened. Closing Settings hands
    /// activation back to it so Zap doesn't linger as the active app — see
    /// `windowWillClose`.
    private weak var appToRestoreOnClose: NSRunningApplication?

    init(preferences: Preferences, inputMode: InputModeReporter, updateChecker: UpdateChecker) {
        self.preferences = preferences
        self.inputMode = inputMode
        self.updateChecker = updateChecker
    }

    func show() {
        // Remember who was in front so closing Settings can return activation to
        // them. Capture only on the way *into* Settings (when Zap isn't already
        // `.regular`); a re-show of the open window has Zap itself frontmost.
        if NSApp.activationPolicy() != .regular {
            let frontmost = NSWorkspace.shared.frontmostApplication
            appToRestoreOnClose = frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier
                ? nil : frontmost
        }

        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(preferences: preferences, inputMode: inputMode, updateChecker: updateChecker))
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
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Critical: don't leave Zap as the active app. It became active (`.regular` +
        // `activate`) to show Settings; if it stays the foreground app, the next
        // ⌘-Tab shows the overlay but selecting an app does nothing — under macOS 14+
        // cooperative activation the switcher's `NSRunningApplication.activate()` is
        // silently ignored while Zap still holds activation. Hand activation back to
        // the app the user came from *before* dropping to `.accessory`, while Zap is
        // still a regular active app — the reliable direction for yielding activation
        // (the switch-time path, where Zap's active state is ambiguous, is not).
        if let previous = appToRestoreOnClose,
           !previous.isTerminated,
           previous.processIdentifier != NSRunningApplication.current.processIdentifier {
            WindowEnumerator.activate(previous)
        }
        appToRestoreOnClose = nil

        // Return to menu-bar-agent behavior (no Dock icon).
        NSApp.setActivationPolicy(.accessory)
    }
}

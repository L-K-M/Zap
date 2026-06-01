import ApplicationServices
import AppKit

/// Thin wrapper around the Accessibility (AX) trust APIs that gate the event tap.
enum AccessibilityAuthorizer {

    /// Whether the process is currently trusted for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility access (shows the system dialog
    /// the first time). Returns the current trust state.
    @discardableResult
    static func prompt() -> Bool {
        // Value of `kAXTrustedCheckOptionPrompt`; used as a literal to avoid
        // cross-SDK differences in how that symbol is imported into Swift.
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens the Accessibility pane in System Settings.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

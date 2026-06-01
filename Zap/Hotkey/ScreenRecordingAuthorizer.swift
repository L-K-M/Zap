import CoreGraphics
import AppKit

/// Thin wrapper around the Screen Recording authorization APIs that gate window
/// capture (used for the optional window previews).
///
/// Mirrors `AccessibilityAuthorizer`. Screen Recording is a *separate*, optional
/// grant from Accessibility — previews are the only feature that needs it, and
/// Zap degrades to text/icon window rows when it's absent.
enum ScreenRecordingAuthorizer {

    /// Whether the process may currently capture screen content. Does not prompt.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Requests Screen Recording access, showing the system prompt the first time.
    /// macOS only applies the grant to a fresh launch, so callers should tell the
    /// user a relaunch may be required. Returns the immediate (pre-relaunch) state.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Opens the Screen Recording pane in System Settings.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}

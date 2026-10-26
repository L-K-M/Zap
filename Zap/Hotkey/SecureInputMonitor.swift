import Carbon.HIToolbox

/// Thin wrapper around the system's secure-event-input state.
///
/// While an app has Secure Keyboard Entry enabled (a focused password field,
/// 1Password/Keychain prompts, Terminal's "Secure Keyboard Entry", some
/// enterprise agents), macOS delivers keyboard events to *no* `CGEventTap` at
/// all: ⌘-Tab silently falls through to the native switcher and Zap looks dead
/// until the state clears. Nothing can intercept those keys — the fix is to
/// make the state visible (menu-bar icon, Permissions tab), so an intermittent
/// baffling failure reads as a legible system condition.
///
/// Mirrors `AccessibilityAuthorizer` / `ScreenRecordingAuthorizer`: one system
/// call, no state of its own. The call is cheap enough for a slow poll.
enum SecureInputMonitor {

    /// Whether any app currently has secure event input enabled.
    static var isEnabled: Bool {
        IsSecureEventInputEnabled()
    }
}

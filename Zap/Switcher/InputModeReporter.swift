import Foundation

/// The trigger mechanism the switcher is currently using. Surfaced to the
/// Settings UI so it can report the *actual* state instead of merely inferring
/// it from the Accessibility permission.
enum SwitcherInputMode: Equatable {
    /// Real ⌘+Tab is intercepted via the event tap (preferred).
    case eventTap
    /// The ⌥+Tab Carbon fallback is active.
    case fallback
    /// Neither the event tap nor the fallback hotkey could be registered.
    case unavailable
    /// Input monitoring is paused from the menu.
    case paused

    var isEventTap: Bool { self == .eventTap }

    /// The status-menu line explaining why ⌘-Tab isn't intercepted, or `nil`
    /// when there's nothing to explain: ⌘-Tab works, the user paused Zap (the
    /// menu already says so), or the user chose ⌥-Tab on purpose
    /// (`alternateForced`). Pure, for unit testing.
    ///
    /// `accessibilityTrusted` separates a fallback caused by a missing grant
    /// from one caused by the event tap failing despite the grant, and
    /// `alternateForced` separates a deliberate ⌥-Tab choice from an accidental
    /// one. The two need different explanations and different fixes.
    func statusMenuWarning(alternateForced: Bool, accessibilityTrusted: Bool) -> String? {
        switch self {
        case .eventTap, .paused:
            return nil
        case .fallback:
            guard !alternateForced else { return nil }
            return accessibilityTrusted
                ? "Using ⌥-Tab: the ⌘-Tab event tap is unavailable"
                : "Using ⌥-Tab: ⌘-Tab needs Accessibility access"
        case .unavailable:
            if alternateForced {
                return "No shortcut works: ⌥-Tab registration failed"
            }
            if accessibilityTrusted {
                return "No shortcut works: the ⌘-Tab event tap is unavailable and ⌥-Tab registration failed"
            }
            return "No shortcut works: ⌘-Tab needs Accessibility access and ⌥-Tab registration failed"
        }
    }

    /// Whether "Open Accessibility Settings…" belongs with the warning. Only a
    /// missing Accessibility grant is fixed by that pane: a deliberate ⌥-Tab
    /// choice and an event-tap failure with the grant already in place are not.
    /// Pure, for unit testing.
    func showsAccessibilityAction(alternateForced: Bool, accessibilityTrusted: Bool) -> Bool {
        guard statusMenuWarning(alternateForced: alternateForced,
                                accessibilityTrusted: accessibilityTrusted) != nil
        else { return false }
        return !alternateForced && !accessibilityTrusted
    }

    /// The form #96 shipped, kept for callers that don't know the trust state.
    /// It models the missing-Accessibility case that motivated the warning.
    func statusMenuWarning(alternateForced: Bool) -> String? {
        statusMenuWarning(alternateForced: alternateForced, accessibilityTrusted: false)
    }
}

/// Observable wrapper so SwiftUI settings views can react to input-mode changes.
final class InputModeReporter: ObservableObject {
    @Published private(set) var mode: SwitcherInputMode

    init(mode: SwitcherInputMode = .unavailable) {
        self.mode = mode
    }

    func update(_ newMode: SwitcherInputMode) {
        guard mode != newMode else { return }
        mode = newMode
    }
}

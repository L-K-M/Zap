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
    func statusMenuWarning(alternateForced: Bool) -> String? {
        switch self {
        case .eventTap, .paused:
            return nil
        case .fallback:
            return alternateForced ? nil : "Using ⌥-Tab: ⌘-Tab needs Accessibility access"
        case .unavailable:
            return "No shortcut works: ⌘-Tab and ⌥-Tab both failed"
        }
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

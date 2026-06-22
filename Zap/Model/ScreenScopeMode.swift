import Foundation

/// How the switcher's app list is scoped on a particular display.
///
/// The setting is stored per physical display (keyed by a stable display UUID; see
/// `ScreenIdentity`), so a multi-monitor setup can, for example, show every app on
/// the main display while a side display lists only what's living on it.
enum ScreenScopeMode: String, CaseIterable, Identifiable {
    /// Full app list, the user's exclusions applied — the default, unchanged behavior.
    case off
    /// Only apps with a window on this display, with the exclusion list applied.
    case scopedRespectingExclusions
    /// Only apps with a window on this display, disregarding the exclusion list — a
    /// window the user put on this display is a stronger relevance signal than a
    /// global "never show" set elsewhere. Hard filters (Zap itself, agent/background
    /// apps) still apply; only the user's exclusion list is ignored.
    case scopedIgnoringExclusions

    var id: String { rawValue }

    /// Whether the list is restricted to apps owning a window on the display.
    var isScoped: Bool { self != .off }

    /// Whether the user's exclusion list is honored. Scoped-ignoring is the only
    /// mode that disregards it.
    var appliesExclusions: Bool { self != .scopedIgnoringExclusions }

    /// Short, user-facing title for the settings picker.
    var title: String {
        switch self {
        case .off: return "Show all apps"
        case .scopedRespectingExclusions: return "Only apps on this display"
        case .scopedIgnoringExclusions: return "Only apps on this display, incl. excluded"
        }
    }
}

import AppKit
import Combine
import SwiftUI

/// A live mirror of the system's accessibility *display* settings, so the overlay
/// can honour them.
///
/// Zap draws a translucent, animated panel over everything else on the screen —
/// exactly the kind of UI "Reduce transparency" and "Reduce motion" exist for. The
/// blur (`NSVisualEffectView`) adapts on its own, but Zap's own tint sits *on top*
/// of it at a user-chosen opacity and would stay see-through regardless, and the
/// panel's animations are ours to suppress.
///
/// An `ObservableObject` so SwiftUI re-renders when the user changes either
/// setting mid-session; `NSWorkspace` posts a notification for both.
final class AccessibilityDisplaySettings: ObservableObject {

    static let shared = AccessibilityDisplaySettings()

    /// Whether the user asked for reduced transparency.
    @Published private(set) var reduceTransparency: Bool

    /// Whether the user asked for reduced motion.
    @Published private(set) var reduceMotion: Bool

    private let workspace: NSWorkspace
    private var observer: NSObjectProtocol?

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        reduceTransparency = workspace.accessibilityDisplayShouldReduceTransparency
        reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let observer {
            workspace.notificationCenter.removeObserver(observer)
        }
    }

    private func refresh() {
        let transparency = workspace.accessibilityDisplayShouldReduceTransparency
        let motion = workspace.accessibilityDisplayShouldReduceMotion
        if reduceTransparency != transparency { reduceTransparency = transparency }
        if reduceMotion != motion { reduceMotion = motion }
    }

    // MARK: Pure rules (unit-tested)

    /// The background opacity actually used: the user's choice normally, fully
    /// opaque when they've asked for reduced transparency. The panel's *colors*
    /// stay exactly as configured — only the see-through-ness goes.
    static func effectiveBackgroundOpacity(configured: Double, reduceTransparency: Bool) -> Double {
        reduceTransparency ? 1 : configured
    }

    /// An animation, or `nil` (an instantaneous change) under reduced motion.
    /// SwiftUI's `.animation(_:value:)` takes an optional for exactly this.
    static func effectiveAnimation(_ animation: Animation?, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

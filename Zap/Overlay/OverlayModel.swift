import SwiftUI

/// Observable state shared between the switcher and the overlay view. Updating
/// `selectedIndex` only moves the highlight — it does not rebuild the window.
final class OverlayModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var selectedIndex: Int = 0

    /// Windows of the currently-selected app, revealed after a dwell. Empty when
    /// the window list is hidden.
    @Published var windows: [WindowInfo] = []
    /// The highlighted window, or `nil` when the app row itself is focused.
    @Published var windowSelectedIndex: Int?

    /// Maximum width the icon row may occupy before it scrolls horizontally.
    /// Set from the target screen so the panel never runs off-screen.
    @Published var maxContentWidth: CGFloat = .greatestFiniteMagnitude

    /// Called when the user clicks an icon. The argument is the app's index.
    var onPick: ((Int) -> Void)?
    /// Called when the pointer hovers an app icon. The argument is the app's index.
    var onHoverApp: ((Int) -> Void)?
    /// Called when the user clicks a window row. The argument is the window's index.
    var onPickWindow: ((Int) -> Void)?
    /// Called when the pointer hovers a window row. The argument is the window's index.
    var onHoverWindow: ((Int) -> Void)?

    var selectedApp: AppInfo? {
        apps.indices.contains(selectedIndex) ? apps[selectedIndex] : nil
    }
}

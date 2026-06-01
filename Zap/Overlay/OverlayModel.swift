import SwiftUI

/// Observable state shared between the switcher and the overlay view. Updating
/// `selectedIndex` only moves the highlight — it does not rebuild the window.
final class OverlayModel: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var selectedIndex: Int = 0

    /// Called when the user clicks an icon. The argument is the app's index.
    var onPick: ((Int) -> Void)?

    var selectedApp: AppInfo? {
        apps.indices.contains(selectedIndex) ? apps[selectedIndex] : nil
    }
}

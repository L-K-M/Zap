import PictKit

/// An immutable pending write to the shared icon store, prepared by an Icons
/// settings row and applied only after the user confirms. Constructing one
/// performs no I/O; the write happens solely in `apply(to:)`, which keeps
/// PictKit's existing clear/pin semantics unchanged.
struct SharedIconChange {

    /// Where the app's icon should come from after the change is applied.
    enum Destination {
        case originalArtwork
        case systemIcon
    }

    let app: AppInfo
    let destination: Destination

    /// The destructive action's label in the confirmation dialog, named for the
    /// shared-store reach the user is about to exercise.
    var actionTitle: String {
        switch destination {
        case .originalArtwork: return "Use Original Artwork Everywhere"
        case .systemIcon: return "Use System Icon Everywhere"
        }
    }

    /// The confirmation dialog's body copy. Says "icon setting" rather than
    /// "custom artwork" because the destination can also remove a system-icon
    /// pin, which stores no artwork at all.
    var confirmationMessage: String {
        let effect = destination == .originalArtwork ? "removed" : "set to the system icon"
        return "The icon setting for \(app.name) will be \(effect) in the local icon store "
            + "shared by Zap, Pict, Jetty and Top Drawer, so it changes in all of them. "
            + "This cannot be undone in Zap. The Dock and Finder are unaffected."
    }

    /// Performs the store write this change represents.
    func apply(to store: IconStore) {
        switch destination {
        case .originalArtwork:
            store.clear(for: app.iconTarget)
        case .systemIcon:
            _ = store.pinToSystemIcon(for: app.iconTarget, writtenBy: "Zap")
        }
    }
}

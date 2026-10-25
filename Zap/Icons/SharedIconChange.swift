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

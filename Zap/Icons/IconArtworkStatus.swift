import Foundation

/// What Settings says about one app's artwork: where its icon is coming from and,
/// when it's the app's own, what shape that artwork is.
///
/// Answering this needs the store and the app bundle — not the resolver's cache —
/// so it lives apart from `IconResolver`, which is about keeping the ⌘-Tab path to
/// a dictionary lookup. Describing an app *decodes* its icon, so it is deliberately
/// blocking and deliberately off the main thread.
struct IconArtworkStatus: Equatable {

    /// The shape of the app's own artwork, or `nil` when none was readable.
    var shape: IconShape?
    /// Whether the user has supplied a file for this app.
    var hasCustomIcon: Bool
    /// Whether this app is pinned to the system icon.
    var isPinnedToSystemIcon: Bool

    var label: String {
        if isPinnedToSystemIcon { return "System icon" }
        if hasCustomIcon { return "Custom icon" }
        guard let shape else { return "No original artwork found" }
        return shape.label
    }

    /// Where the queue for batch description lives. Utility rather than user
    /// initiated: nothing on screen is waiting on it except a caption.
    private static let queue = DispatchQueue(label: "com.zapapp.icon-status", qos: .utility)

    /// Describes one app. Decodes its bundle artwork, so it blocks — call it off
    /// the main thread.
    static func describe(_ identity: IconIdentity, store: IconStore) -> IconArtworkStatus {
        if store.entry(for: identity)?.origin == .system {
            return IconArtworkStatus(shape: nil, hasCustomIcon: false, isPinnedToSystemIcon: true)
        }
        if store.imageURL(for: identity) != nil {
            return IconArtworkStatus(shape: nil, hasCustomIcon: true, isPinnedToSystemIcon: false)
        }
        // By identifier: this rung is about the app bundle's *own* artwork, and a
        // wrapper that borrowed an identifier shows what's behind it.
        let shape = BundleArtwork.image(forBundleID: identity.bundleIdentifier)
            .map { IconShapeClassifier.classify($0) }
        return IconArtworkStatus(shape: shape, hasCustomIcon: false, isPinnedToSystemIcon: false)
    }

    /// Describes several apps off the main thread, calling `completion` back on it.
    /// Keyed by `IconIdentity.storageKey`, which is what the rows look them up by.
    static func load(for identities: [IconIdentity], store: IconStore,
                     completion: @escaping ([String: IconArtworkStatus]) -> Void) {
        queue.async {
            var result: [String: IconArtworkStatus] = [:]
            for identity in identities {
                result[identity.storageKey] = describe(identity, store: store)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

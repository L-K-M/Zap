import AppKit
import PictKit

/// A lightweight, value-type snapshot of a switchable application.
///
/// Built from an `NSRunningApplication` but decoupled from it so the switcher hot
/// path and the unit tests can work with plain values.
struct AppInfo: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String
    let processIdentifier: pid_t
    let icon: NSImage?

    /// Whether the app was hidden (⌘H) when this snapshot was taken. Captured so
    /// the overlay can mark hidden apps — the native switcher gives no hint that
    /// an app has been hidden, which makes ⌘H feel like the app vanished.
    /// Snapshot-only: it is not part of the app's identity (see `==`).
    let isHidden: Bool

    /// Where the app bundle lives. Carried because a bundle identifier does not
    /// identify an app on its own — site-specific-browser wrappers all report the
    /// browser's — and the icon store needs the path to tell them apart.
    let bundleURL: URL?

    /// Unique per running process. Two instances of the same app share a bundle
    /// identifier, so the pid is needed to keep SwiftUI `ForEach` IDs distinct
    /// and to activate the correct process.
    var id: String { "\(bundleIdentifier):\(processIdentifier)" }

    /// How the shared icon store knows this app.
    var iconTarget: IconTarget {
        .application(bundleURL: bundleURL, bundleIdentifier: bundleIdentifier)
    }

    /// The store's key for this app, serialised — what settings rows and status
    /// lookups are keyed by. `nil` is unreachable for a real app (it would need
    /// neither a path nor an identifier) but the type admits it, so callers check.
    var storeKey: String? { IconEntryKey.storageKey(for: iconTarget)?.serialized }

    /// How the MRU order knows this app: the icon store's key *value* — bundle path
    /// when known, identifier otherwise. Both need wrapper apps that share a bundle
    /// identifier told apart, so they share one notion of identity.
    ///
    /// **`value`, not `serialized`.** The serialized form carries a `kind:` prefix
    /// the store needs to tell an app from a file, and the MRU has no use for it —
    /// it only ever holds applications. It also cannot have it: MRU order is
    /// persisted, every stored key predates the shared store and is bare, and
    /// prefixing the lookup would silently stop matching all of them. The user's
    /// switcher order would reset on upgrade, which `AGENTS.md` names as the one
    /// feel not to break.
    var mruKey: String {
        IconEntryKey.storageKey(for: iconTarget)?.value ?? bundleIdentifier
    }

    /// Designated initializer (also used by tests).
    init(bundleIdentifier: String, name: String, processIdentifier: pid_t,
         icon: NSImage? = nil, isHidden: Bool = false, bundleURL: URL? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.processIdentifier = processIdentifier
        self.icon = icon
        self.isHidden = isHidden
        self.bundleURL = bundleURL
    }

    /// Builds an `AppInfo` from a running application, or returns `nil` when the
    /// app should never appear in the switcher (background/agent apps, or apps
    /// without a bundle identifier).
    init?(runningApplication app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return nil }
        guard let bundleID = app.bundleIdentifier else { return nil }
        self.init(
            bundleIdentifier: bundleID,
            name: app.localizedName ?? bundleID,
            processIdentifier: app.processIdentifier,
            icon: app.icon,
            isHidden: app.isHidden,
            bundleURL: app.bundleURL
        )
    }

    /// Returns a copy drawing `icon` instead of the one captured from the running
    /// application. Lets `AppListProvider` swap in un-jailed artwork while
    /// `AppInfo` stays a dumb value type that knows nothing about icon resolution.
    /// Identity is unaffected — `==` ignores the icon — so a substitution can't
    /// perturb selection or the MRU order.
    func replacingIcon(_ icon: NSImage?) -> AppInfo {
        AppInfo(bundleIdentifier: bundleIdentifier, name: name,
                processIdentifier: processIdentifier, icon: icon, isHidden: isHidden,
                bundleURL: bundleURL)
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.processIdentifier == rhs.processIdentifier
    }
}

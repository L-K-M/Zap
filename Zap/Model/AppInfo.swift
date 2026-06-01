import AppKit

/// A lightweight, value-type snapshot of a switchable application.
///
/// Built from an `NSRunningApplication` but decoupled from it so the switcher hot
/// path and the unit tests can work with plain values.
struct AppInfo: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String
    let processIdentifier: pid_t
    let icon: NSImage?

    /// Unique per running process. Two instances of the same app share a bundle
    /// identifier, so the pid is needed to keep SwiftUI `ForEach` IDs distinct
    /// and to activate the correct process.
    var id: String { "\(bundleIdentifier):\(processIdentifier)" }

    /// Designated initializer (also used by tests).
    init(bundleIdentifier: String, name: String, processIdentifier: pid_t, icon: NSImage? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.processIdentifier = processIdentifier
        self.icon = icon
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
            icon: app.icon
        )
    }

    static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.processIdentifier == rhs.processIdentifier
    }
}

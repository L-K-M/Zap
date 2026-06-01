import AppKit

/// Provides the ordered, filtered list of switchable apps.
///
/// Combines the live list of running applications (`NSWorkspace`) with MRU
/// ordering and the user's exclusion list.
final class AppListProvider {

    private let preferences: Preferences
    private let mru = MRUTracker()
    private var activationObserver: NSObjectProtocol?

    init(preferences: Preferences) {
        self.preferences = preferences
        seedMRU()
        observeActivations()
    }

    deinit {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: Public

    /// The current switcher list: regular apps, MRU-ordered, with exclusions removed.
    func currentApps() -> [AppInfo] {
        // Always exclude Zap itself. While the Settings window is open the app
        // temporarily becomes `.regular`, which would otherwise let it satisfy
        // `AppInfo`'s activation-policy check and appear in its own switcher.
        let ownBundleID = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications
            .compactMap(AppInfo.init(runningApplication:))
            .filter { $0.bundleIdentifier != ownBundleID }
        return Self.filtered(mru.ordered(running), excluding: preferences.excludedBundleIDs)
    }

    /// Resolves the live running application for an `AppInfo`.
    func runningApplication(for info: AppInfo) -> NSRunningApplication? {
        let byBundle = NSRunningApplication
            .runningApplications(withBundleIdentifier: info.bundleIdentifier)
        return byBundle.first { $0.processIdentifier == info.processIdentifier }
            ?? byBundle.first
            ?? NSRunningApplication(processIdentifier: info.processIdentifier)
    }

    /// The bundle identifier of the currently frontmost application, if any.
    /// Used to decide the initial switcher selection.
    func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Pure exclusion filter — exposed for unit testing.
    static func filtered(_ apps: [AppInfo], excluding excluded: Set<String>) -> [AppInfo] {
        apps.filter { !excluded.contains($0.bundleIdentifier) }
    }

    // MARK: Private

    private func seedMRU() {
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            mru.recordActivation(bundleID: front)
        }
    }

    private func observeActivations() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let bundleID = app.bundleIdentifier
            else { return }
            self?.mru.recordActivation(bundleID: bundleID)
        }
    }
}

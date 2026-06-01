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
        let running = NSWorkspace.shared.runningApplications
            .compactMap(AppInfo.init(runningApplication:))
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

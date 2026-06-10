import AppKit

/// Provides the ordered, filtered list of switchable apps.
///
/// Combines the live list of running applications (`NSWorkspace`) with MRU
/// ordering and the user's exclusion list.
final class AppListProvider {

    private let preferences: Preferences
    private let defaults: UserDefaults
    private let mru: MRUTracker
    private let ownBundleID = Bundle.main.bundleIdentifier
    private var activationObserver: NSObjectProtocol?

    /// `UserDefaults` key under which the MRU order is persisted across launches.
    private static let mruOrderKey = "mruOrder"
    /// How many bundle identifiers to persist — generous for any realistic app set
    /// while keeping the stored array bounded.
    private static let mruPersistLimit = 50

    init(preferences: Preferences, defaults: UserDefaults = .standard) {
        self.preferences = preferences
        self.defaults = defaults
        // Seed from the previous session's order so the first ⌘-Tab after launch
        // highlights a sensible "previous" app instead of process-table order.
        self.mru = MRUTracker(order: defaults.stringArray(forKey: Self.mruOrderKey) ?? [])
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
        let running = NSWorkspace.shared.runningApplications
            .compactMap(AppInfo.init(runningApplication:))
            .filter { !isOwnBundleID($0.bundleIdentifier) }
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
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return bundleID.flatMap { isOwnBundleID($0) ? nil : $0 }
    }

    /// Pure exclusion filter — exposed for unit testing.
    static func filtered(_ apps: [AppInfo], excluding excluded: Set<String>) -> [AppInfo] {
        apps.filter { !excluded.contains($0.bundleIdentifier) }
    }

    // MARK: Private

    private func seedMRU() {
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           !isOwnBundleID(front) {
            mru.recordActivation(bundleID: front)
            persistMRU()
        }
    }

    /// Saves the (capped) MRU order so the next launch can seed from it.
    private func persistMRU() {
        defaults.set(Array(mru.order.prefix(Self.mruPersistLimit)), forKey: Self.mruOrderKey)
    }

    private func isOwnBundleID(_ bundleID: String) -> Bool {
        guard let ownBundleID else { return false }
        return ownBundleID == bundleID
    }

    private func observeActivations() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let bundleID = app.bundleIdentifier,
                !isOwnBundleID(bundleID)
            else { return }
            mru.recordActivation(bundleID: bundleID)
            persistMRU()
        }
    }
}

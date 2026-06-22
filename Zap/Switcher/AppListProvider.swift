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
        currentApps(mode: .off, pidsOnScreen: [])
    }

    /// The switcher list for a display with scope `mode`. When `mode` is `.off`,
    /// this is the full list with exclusions applied. When scoped, only apps owning a
    /// window on the display (`pidsOnScreen`) survive, and the user's exclusions are
    /// applied unless the mode disregards them. Zap itself and non-regular apps are
    /// always filtered out regardless of mode.
    func currentApps(mode: ScreenScopeMode, pidsOnScreen: Set<pid_t>) -> [AppInfo] {
        // Always exclude Zap itself. While the Settings window is open the app
        // temporarily becomes `.regular`, which would otherwise let it satisfy
        // `AppInfo`'s activation-policy check and appear in its own switcher.
        let running = NSWorkspace.shared.runningApplications
            .compactMap(AppInfo.init(runningApplication:))
            .filter { !isOwnBundleID($0.bundleIdentifier) }
        return Self.scoped(mru.ordered(running), mode: mode, pidsOnScreen: pidsOnScreen,
                           excluding: preferences.excludedBundleIDs)
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

    /// Pure screen-scope + exclusion filter — exposed for unit testing. Applies the
    /// screen filter first (keeping only apps in `pidsOnScreen`) when the mode is
    /// scoped, then the exclusion list unless the mode disregards it. Order is
    /// preserved throughout.
    static func scoped(_ apps: [AppInfo], mode: ScreenScopeMode,
                       pidsOnScreen: Set<pid_t>, excluding excluded: Set<String>) -> [AppInfo] {
        let onScreen = mode.isScoped
            ? apps.filter { pidsOnScreen.contains($0.processIdentifier) }
            : apps
        return mode.appliesExclusions ? filtered(onScreen, excluding: excluded) : onScreen
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

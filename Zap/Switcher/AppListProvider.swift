import AppKit
import PictKit

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

    /// Supplies un-jailed artwork, if the feature is wired up. Absent in tests and
    /// whenever icon substitution is off, in which case the system icon captured
    /// by `AppInfo` is used unchanged.
    private let iconResolver: IconResolver?

    /// `UserDefaults` key under which the MRU order is persisted across launches.
    private static let mruOrderKey = "mruOrder"
    /// How many MRU keys to persist — generous for any realistic app set
    /// while keeping the stored array bounded.
    private static let mruPersistLimit = 50
    /// How often the persisted MRU order may be refreshed. Every system-wide
    /// activation reorders the list; writing it out on each one turns one of the
    /// most frequent events on the machine into a `UserDefaults` write. Losing
    /// the last interval's activations to a crash costs at most a slightly stale
    /// seed on the next launch, which live activations correct anyway.
    private static let mruPersistInterval: TimeInterval = 2

    /// When the MRU order was last written out. `nil` until the first write.
    private var lastPersistAt: TimeInterval?

    init(preferences: Preferences, defaults: UserDefaults = .standard,
         iconResolver: IconResolver? = nil) {
        self.preferences = preferences
        self.defaults = defaults
        self.iconResolver = iconResolver
        // Seed from the previous session's order so the first ⌘-Tab after launch
        // highlights a sensible "previous" app instead of process-table order.
        self.mru = MRUTracker(order: defaults.stringArray(forKey: Self.mruOrderKey) ?? [])
        seedMRU()
        observeActivations()
    }

    deinit {
        // Flush anything the throttle held back.
        persistMRU()
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
        // Always exclude Zap itself independently of activation policy. The app is
        // an accessory today; this explicit invariant prevents a future own-window
        // change from ever putting Zap in its own switcher.
        let running = NSWorkspace.shared.runningApplications
            .compactMap(AppInfo.init(runningApplication:))
            .filter { !isOwnBundleID($0.bundleIdentifier) }
            .map(substitutingIcon)
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

    /// The MRU key of the currently frontmost application, if any.
    /// Used to decide the initial switcher selection. A key, not a bundle
    /// identifier: comparing identifiers would mistake one Chrome wrapper for
    /// another (see `AppInfo.mruKey`).
    func frontmostAppKey() -> String? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier,
              !isOwnBundleID(bundleID) else { return nil }
        return Self.mruKey(bundleID: bundleID, bundleURL: front.bundleURL)
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

    /// Swaps in un-jailed artwork when the resolver already has it. A cache miss
    /// leaves the system icon in place and warms in the background, so this stays
    /// a dictionary lookup on the ⌘-Tab path (`SHARED-ICONS.md §6.4`).
    private func substitutingIcon(_ info: AppInfo) -> AppInfo {
        guard let icon = iconResolver?.icon(for: info.iconTarget) else { return info }
        return info.replacingIcon(icon)
    }

    /// The MRU key for a live process — `AppInfo.mruKey` without the snapshot,
    /// so activations and snapshots agree on what identifies an app.
    private static func mruKey(bundleID: String, bundleURL: URL?) -> String {
        // `value`, not `serialized` — see `AppInfo.mruKey`. Persisted MRU keys are
        // bare, so the `kind:` prefix would stop matching every one of them.
        IconEntryKey.storageKey(for: .application(bundleURL: bundleURL,
                                                  bundleIdentifier: bundleID))?.value
            ?? bundleID
    }

    private func seedMRU() {
        guard let key = frontmostAppKey() else { return }
        mru.recordActivation(key: key)
        persistMRUIfDue()
    }

    /// Saves the (capped) MRU order so the next launch can seed from it.
    /// Unthrottled: only the launch seed and teardown flush come here directly.
    private func persistMRU() {
        defaults.set(Array(mru.order.prefix(Self.mruPersistLimit)), forKey: Self.mruOrderKey)
    }

    /// Persists the MRU order at most once per `mruPersistInterval`.
    private func persistMRUIfDue() {
        let now = Date.timeIntervalSinceReferenceDate
        guard Self.shouldPersist(now: now, lastPersistAt: lastPersistAt,
                                 interval: Self.mruPersistInterval) else { return }
        lastPersistAt = now
        persistMRU()
    }

    /// Pure throttle rule: the first write always passes, then at most one per
    /// `interval` (a zero interval disables the throttle). Extracted for unit
    /// testing.
    static func shouldPersist(now: TimeInterval, lastPersistAt: TimeInterval?,
                              interval: TimeInterval) -> Bool {
        guard let lastPersistAt else { return true }
        return interval <= 0 || now - lastPersistAt >= interval
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
            mru.recordActivation(key: Self.mruKey(bundleID: bundleID, bundleURL: app.bundleURL))
            persistMRUIfDue()
        }
    }
}

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

    /// Resolves the live running application for an `AppInfo`, or `nil` when no
    /// running process still matches the snapshot's identity.
    ///
    /// Looks up only the snapshot's pid, then verifies the candidate against
    /// `matchesSnapshot`. There is deliberately no bundle-identifier fallback:
    /// resolving to a *different* process of the same app — or to an arbitrary
    /// browser process sharing a site-specific-browser wrapper's bundle ID —
    /// would activate, hide, or terminate the wrong app.
    func runningApplication(for info: AppInfo) -> NSRunningApplication? {
        guard let candidate = NSRunningApplication(processIdentifier: info.processIdentifier),
              Self.matchesSnapshot(info,
                                   processIdentifier: candidate.processIdentifier,
                                   bundleIdentifier: candidate.bundleIdentifier,
                                   bundleURL: candidate.bundleURL,
                                   isTerminated: candidate.isTerminated) else {
            return nil
        }
        return candidate
    }

    /// Whether a live process still matches an `AppInfo` snapshot — exposed for
    /// unit testing. Requires a positive pid equal to the snapshot's, a
    /// nonterminated process, and the exact bundle identifier. When the snapshot
    /// carries a `bundleURL`, the live candidate must report the same
    /// standardized file URL, telling wrapper apps that share a bundle
    /// identifier apart by path. A snapshot without a `bundleURL` is satisfied
    /// by pid + bundle identifier alone.
    ///
    /// This does not guard against pid reuse by a later process with the same
    /// bundle identifier *and* path: `AppInfo` captures no launch date to tell
    /// that case apart.
    static func matchesSnapshot(_ info: AppInfo, processIdentifier: pid_t,
                                bundleIdentifier: String?, bundleURL: URL?,
                                isTerminated: Bool) -> Bool {
        guard processIdentifier > 0,
              processIdentifier == info.processIdentifier,
              !isTerminated,
              bundleIdentifier == info.bundleIdentifier else { return false }
        guard let snapshotURL = info.bundleURL else { return true }
        return bundleURL?.standardizedFileURL == snapshotURL.standardizedFileURL
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
        persistMRU()
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
            mru.recordActivation(key: Self.mruKey(bundleID: bundleID, bundleURL: app.bundleURL))
            persistMRU()
        }
    }
}

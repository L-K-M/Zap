import AppKit
import Combine
import PictKit

/// Zap's side of the shared icon store.
///
/// `PictKit` owns the store, the resolution ladder and the cache. What it
/// deliberately does *not* own is any app's settings screen — `IconResolver` used
/// to take a `Preferences` and subscribe to it with Combine, which bound the
/// resolver to Zap's Appearance tab and made it useless to Jetty, which has no
/// icon-size slider, and to Pict, which has no switcher row to bleed into.
///
/// So this is the seam: everything that used to be inside `IconResolver` and is
/// really *about Zap* — which preference means what, when a change is worth
/// re-rendering for, and which apps are worth warming — lives here.
final class ZapIcons {

    /// Thread-safe by construction — `IconResolver` guards its cache with a lock and
    /// does its work on its own queue — so this type carries no actor isolation.
    ///
    /// It cannot have any: `AppDelegate` is not `@MainActor`, so a `@MainActor` init
    /// here is uncallable from `private lazy var icons = ZapIcons(...)`, and
    /// `AppListProvider` reads `resolver` from the ⌘-Tab path. Everything that really
    /// is main-thread-only — `NSScreen.screens`, the `@Published` subscriptions — is
    /// already delivered on the main queue by the publisher or the notification
    /// centre, so the isolation was buying nothing and costing the call sites.
    let resolver: IconResolver
    let store: IconStore

    private let preferences: Preferences
    private var cancellables: Set<AnyCancellable> = []
    private var workspaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var watcher: IconStoreWatcher?

    init(preferences: Preferences, store: IconStore = IconStore()) {
        // `options(from:)` reads `NSScreen.screens`, which is main-thread-only, and
        // this type carries no actor isolation to enforce that (see `resolver`). The
        // contract is real but implicit — `AppDelegate` first touches its lazy
        // `icons` during launch — so assert it rather than trusting it. Off-main,
        // `NSScreen.screens` can answer empty and every icon caches at the wrong
        // size, with nothing to show for it.
        dispatchPrecondition(condition: .onQueue(.main))
        self.preferences = preferences
        self.store = store
        self.resolver = IconResolver(options: Self.options(from: preferences), store: store)

        subscribe()
        watchTheStore()
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    // MARK: Warming

    /// Resolves every running app's icon ahead of time, so the first ⌘-Tab after
    /// launch already has un-jailed artwork rather than warming under the keystroke.
    func warmRunningApps() {
        resolver.warm(NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier else { return nil }
            return IconTarget.application(bundleURL: app.bundleURL, bundleIdentifier: bundleID)
        })
    }

    // MARK: Preferences → render options

    /// Maps the current settings onto what the resolver needs.
    ///
    /// The pixel size is computed here rather than in the package because it needs
    /// `NSScreen`, which is main-thread-only — and the resolver does its work on a
    /// background queue, so it must never reach for one.
    private static func options(from preferences: Preferences) -> IconRenderOptions {
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        return IconRenderOptions(
            mode: preferences.iconSourceMode,
            pixelSize: IconBitmap.pixelSize(forIconSize: preferences.iconSize, scale: scale),
            scale: scale,
            bleed: preferences.iconBleed,
            trimsTransparentEdges: preferences.iconTrimTransparentEdges,
            drawsShadow: preferences.iconShadow)
    }

    /// Hands the resolver the current options. Cheap to call on any change:
    /// `IconRenderOptions` is `Equatable` and identical options are a comparison and
    /// a return, not a cache flush.
    private func apply() {
        resolver.update(Self.options(from: preferences))
    }

    private func subscribe() {
        // `dropFirst` throughout: a `@Published` publisher replays its current value
        // on subscribe, and every one of these is already in the initial options.

        // What gets drawn — invalidates immediately.
        //
        // `receive(on:)` on all three: `apply()` reads `NSScreen.screens`, which is
        // main-thread-only, and `@Published` emits on whatever thread wrote the
        // property. Today every write comes from a SwiftUI control on the main
        // thread, so this changes nothing — but it stops a future background write
        // from turning into a main-thread-only call off-main, and it matches what
        // the debounced subscriptions below already do via `RunLoop.main`.
        preferences.$iconSourceMode
            .dropFirst().removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        preferences.$iconTrimTransparentEdges
            .dropFirst().removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        preferences.$iconShadow
            .dropFirst().removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        // Size and bleed come off sliders, so a drag would otherwise re-render every
        // icon on every frame of it.
        preferences.$iconSize
            .dropFirst().removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        preferences.$iconBleed
            .dropFirst().removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &cancellables)

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }
            self?.resolver.warm([.application(bundleURL: app.bundleURL,
                                              bundleIdentifier: bundleID)])
        }

        // Plugging in a sharper display makes every cached icon too soft for it, and
        // the icon size alone would never notice. `apply()` compares before acting,
        // so an irrelevant display change costs nothing.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.apply()
        }
    }

    // MARK: The other writers

    /// Re-reads the store when another app changes it.
    ///
    /// This is what makes the store *shared* rather than merely common: set an icon
    /// in Pict and it appears in the switcher, rather than at Zap's next launch.
    private func watchTheStore() {
        watcher = IconStoreWatcher(store: store) { [weak self] in
            self?.resolver.invalidate()
        }
        watcher?.start()
    }

    // MARK: Migration

    /// Carries icons set in earlier versions of Zap into the shared store.
    ///
    /// Runs once — the old directory is renamed afterwards, so every later launch is
    /// a `fileExists` and a return. Called before anything reads the store, so a
    /// user upgrading never sees a switcher that briefly forgot their icons.
    static func migrateIfNeeded(into store: IconStore) {
        let outcome = ZapManifestImport.run(into: store)
        guard outcome.imported > 0 || outcome.skipped > 0 else { return }
        // `%ld`, not `%d`: Swift's `Int` is 64-bit on every Apple platform, and a
        // variadic `%d` truncates it.
        NSLog("Zap: moved %ld icon(s) into the shared Pict store (%ld skipped).",
              outcome.imported, outcome.skipped)
    }
}

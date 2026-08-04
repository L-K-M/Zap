import AppKit

/// Returns activation to the last external app after Zap finishes presenting UI
/// of its own. Tracking the whole presentation avoids restoring a stale app when
/// the user switches elsewhere before closing the window or alert.
final class ActivationHandoff {

    private static let ownPID = NSRunningApplication.current.processIdentifier
    private static var presentationCount = 0
    private static var generation = 0
    private static var target: NSRunningApplication?
    private static var activationObserver: NSObjectProtocol?

    private var isTracking = true

    /// How many Zap presentations are currently open. For tests: the nesting rule
    /// — only the last one to close hands activation back — is the part of this
    /// type most likely to break silently, and it is otherwise unobservable.
    static var openPresentations: Int { presentationCount }

    init() {
        assert(Thread.isMainThread)
        Self.presentationCount += 1
        Self.generation &+= 1
        if Self.presentationCount == 1 { Self.startObserving() }
    }

    deinit {
        finish(shouldRestore: false)
    }

    /// Ends this presentation. Nested Zap UI shares the same handoff, so only the
    /// final window or alert to close returns activation to the external app.
    func restore() {
        finish(shouldRestore: true)
    }

    /// Restore only while Zap still owns activation. A different active app is a
    /// newer user choice and must never be replaced by a stale handoff.
    static func shouldRestore(targetPID: pid_t, targetIsTerminated: Bool,
                              zapIsActive: Bool, ownPID: pid_t) -> Bool {
        !targetIsTerminated && targetPID != ownPID && zapIsActive
    }

    private func finish(shouldRestore: Bool) {
        guard isTracking else { return }
        assert(Thread.isMainThread)
        isTracking = false
        Self.presentationCount -= 1
        guard Self.presentationCount == 0 else { return }

        let target = Self.target

        // `shouldRestore` first, then read `NSApp` once. It was sampled twice on
        // the same path, which left the tested predicate's `zapIsActive` argument
        // looking like an open question when the guard here has already settled it,
        // and invited the two reads to drift apart under a later edit. Ordering
        // matters as well as counting: a presentation dropped without `restore()`
        // must return before touching `NSApp` at all.
        guard shouldRestore else { return }
        let zapIsActive = NSApp.isActive
        guard zapIsActive else { return }
        guard let target,
              Self.shouldRestore(targetPID: target.processIdentifier,
                                 targetIsTerminated: target.isTerminated,
                                 zapIsActive: zapIsActive,
                                 ownPID: Self.ownPID) else {
            NSApp.deactivate()
            return
        }

        let generation = Self.generation
        guard WindowEnumerator.activate(target) else {
            NSApp.deactivate()
            return
        }

        // Activation is asynchronous even when the request returns true. If Zap
        // still owns focus after the request has had time to settle, explicitly
        // resign it; a newly-opened Zap presentation cancels this fallback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard Self.presentationCount == 0,
                  Self.generation == generation,
                  NSApp.isActive else { return }
            NSApp.deactivate()
        }
    }

    private static func startObserving() {
        if activationObserver == nil {
            // Keep this observer for the process lifetime. A minimized Settings
            // window has no active handoff, but an app used while it is minimized
            // must still become the target when Settings is restored from the Dock.
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                record(app)
            }
        }
        // Subscribe first, then sample, so an activation cannot fall between the
        // initial snapshot and observer installation.
        record(NSWorkspace.shared.frontmostApplication)
    }

    private static func record(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ownPID else { return }
        target = app
    }
}

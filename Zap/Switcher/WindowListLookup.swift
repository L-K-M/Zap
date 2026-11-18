import Foundation

/// Runs window-list enumeration off the main thread and decides when its result
/// may be shown.
///
/// `WindowEnumerator.windows` is synchronous IPC into the target app. On the
/// main thread it stalls the run loop that carries the ⌘+Tab event tap, so
/// lookups run on a private queue with at most one in flight. A lookup captures
/// the generation current when it starts, and its result is reported only while
/// that generation is still current — that is how selection and session changes
/// discard stale lists. A lookup that found fewer than two windows marks the
/// generation exhausted so ↓ cannot make it repeat the query.
/// The controller owns the lookup state on the main thread. Only the operation’s
/// enumeration runs on the worker queue.
final class WindowListLookup {

    /// Why a lookup was started; decides whether its result takes the window
    /// focus.
    enum Reason {
        /// The dwell timer fired: reveal the list, keep the app row focused.
        case dwell
        /// ↓ was pressed: reveal the list and focus the first window.
        case immediateReveal
    }

    /// A finished lookup that still belongs to the current selection.
    struct Result {
        let pid: pid_t
        let windows: [WindowInfo]
        /// Whether the trigger that asked for the list (↓) wants the first
        /// window focused, rather than the list just being revealed.
        let focusFirst: Bool
    }

    /// The enumeration backend, injectable for tests. `isCancelled` is
    /// consulted between AX round-trips.
    typealias Enumeration = (_ pid: pid_t, _ includeFullScreenWindows: Bool,
                            _ isCancelled: @escaping () -> Bool) -> [WindowInfo]

    private static let defaultEnumeration: Enumeration = { pid, includeFullScreenWindows, isCancelled in
        WindowEnumerator.windows(forPID: pid,
                                 includeFullScreenWindows: includeFullScreenWindows,
                                 isCancelled: isCancelled)
    }

    /// Serial, single-concurrency worker: at most one AX enumeration runs at a
    /// time, so a burst of selection changes cannot pile up concurrent IPC.
    private static func makeQueue() -> OperationQueue {
        let queue = OperationQueue()
        queue.name = "ch.lkmc.Zap.window-list-lookup"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }

    private final class LookupOperation: Operation, @unchecked Sendable {
        private let pid: pid_t
        private let includeFullScreenWindows: Bool
        private let enumerate: Enumeration
        private let onFinish: (LookupOperation, [WindowInfo]) -> Void

        init(pid: pid_t, includeFullScreenWindows: Bool, enumerate: @escaping Enumeration,
             onFinish: @escaping (LookupOperation, [WindowInfo]) -> Void) {
            self.pid = pid
            self.includeFullScreenWindows = includeFullScreenWindows
            self.enumerate = enumerate
            self.onFinish = onFinish
            super.init()
        }

        override func main() {
            guard !isCancelled else { return }
            let found = enumerate(pid, includeFullScreenWindows) { [weak self] in
                self?.isCancelled ?? true
            }
            guard !isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isCancelled else { return }
                self.onFinish(self, found)
            }
        }
    }

    private let queue = makeQueue()
    private let enumerate: Enumeration
    private var operation: LookupOperation?
    private var state = WindowLookupState()

    init(enumerate: @escaping Enumeration = defaultEnumeration) {
        self.enumerate = enumerate
    }

    /// Whether a lookup is queued or running for the current generation.
    var isPending: Bool { state.isPending }

    /// Drops any pending result. Call when the selected app or session changes.
    func invalidate() {
        state.invalidate()
        operation?.cancel()
        operation = nil
    }

    /// Marks the pending lookup to focus the first window on arrival. Used when
    /// ↓ arrives while the dwell's lookup is already running, so no second query
    /// is started.
    func adoptPendingForImmediateReveal() {
        state.adoptPendingForImmediateReveal()
    }

    /// What ↓ should do when `windowsShown` is false.
    func downAction(windowsShown: Bool, dwellPending: Bool, enabled: Bool) -> WindowLookupState.DownAction {
        state.downAction(windowsShown: windowsShown, dwellPending: dwellPending, enabled: enabled)
    }

    /// Starts a lookup for `pid`. Returns `false` when a lookup is already
    /// pending or this generation is exhausted; the caller then either adopts
    /// the pending one (↓) or does nothing (dwell).
    @discardableResult
    func start(pid: pid_t, includeFullScreenWindows: Bool, reason: Reason,
               completion: @escaping (Result) -> Void) -> Bool {
        guard operation == nil, !state.isPending,
              state.exhaustedGeneration != state.generation
        else { return false }

        state.start(focusesFirst: reason == .immediateReveal)
        let operation = LookupOperation(pid: pid,
                                        includeFullScreenWindows: includeFullScreenWindows,
                                        enumerate: enumerate) { [weak self] operation, found in
            guard let self, self.operation === operation else { return }
            self.operation = nil
            guard let focusFirst = self.state.finish(foundWindowCount: found.count) else { return }
            completion(Result(pid: pid, windows: found, focusFirst: focusFirst))
        }
        self.operation = operation
        queue.addOperation(operation)
        return true
    }
}

import Foundation

/// Bookkeeping for the window-list lookup of the current app selection.
///
/// The lookup itself is synchronous Accessibility IPC and runs on a private
/// queue (see `WindowListLookup`); this value type tracks whether a result may
/// still be applied and whether ↓ needs a new lookup. It holds no AX state and
/// is pure, so the controller's decision is unit-testable.
struct WindowLookupState {

    /// What ↓ should do when no window list is on screen.
    enum DownAction: Equatable {
        /// Start a lookup now; its result focuses the first window.
        case start
        /// A lookup is already running; mark it to focus the first window.
        case adoptPending
        /// Nothing to do.
        case none
    }

    /// Monotonic token for the current selection/session. A lookup captures it
    /// and is applied only while it still matches.
    private(set) var generation = 0

    /// The generation whose lookup already finished and found fewer than two
    /// windows, so ↓ must not repeat that query for the same selection.
    private(set) var exhaustedGeneration: Int?

    /// Whether a lookup is queued or running for the current generation.
    private(set) var isPending = false

    /// Whether the pending lookup should focus the first window when it lands
    /// (↓ arrived while the dwell's lookup was already running).
    private(set) var pendingFocusesFirst = false

    /// Drops any pending result and makes the next lookup current. Called when
    /// the selected app or session changes.
    mutating func invalidate() {
        generation += 1
        exhaustedGeneration = nil
        isPending = false
        pendingFocusesFirst = false
    }

    /// Starts a lookup for the current generation.
    mutating func start(focusesFirst: Bool) {
        isPending = true
        pendingFocusesFirst = focusesFirst
    }

    /// ↓ arrived while a lookup was already running: keep it (no second query)
    /// but let its result take the window focus.
    mutating func adoptPendingForImmediateReveal() {
        pendingFocusesFirst = true
    }

    /// Finishes the pending lookup. Returns the focus its result should get
    /// when it found enough windows to show, or `nil` when it found fewer than
    /// two (which marks the generation exhausted).
    mutating func finish(foundWindowCount count: Int) -> Bool? {
        isPending = false
        let focusesFirst = pendingFocusesFirst
        pendingFocusesFirst = false
        guard count >= 2 else {
            exhaustedGeneration = generation
            return nil
        }
        return focusesFirst
    }

    /// What ↓ should do while `windowsShown` is false. `dwellPending` means the
    /// dwell timer is still armed (or the panel hasn't appeared yet), and
    /// `enabled` is the window-list preference together with the AX grant.
    func downAction(windowsShown: Bool, dwellPending: Bool, enabled: Bool) -> DownAction {
        guard !windowsShown, enabled else { return .none }
        if isPending { return .adoptPending }
        if exhaustedGeneration == generation { return .none }
        return dwellPending ? .start : .none
    }
}

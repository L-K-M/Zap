import Foundation

/// Bounds how many SVGs rasterise at the same time.
///
/// Every render stands up a `WKWebView` — twice, since transparency comes from two
/// passes (`SVGRasterizer`) — and a web view is not a cheap object to have several
/// of. Nothing enforced a ceiling before because nothing could ask for many at
/// once: the search sheet renders previews strictly one after another, and an
/// import is one file.
///
/// Icon sets change that arithmetic rather than the code. A theme is thousands of
/// SVGs the user is now expected to browse, adopting from a set is a render, and
/// the icon list will happily start an import on every row at once. None of those
/// paths knows about the others, so the ceiling belongs somewhere all of them pass
/// through, which is here.
///
/// Two rather than one. One would serialise the preview loop against a file the
/// user drops mid-browse, and make the drop look ignored until the grid finished.
///
/// **No cancellation handling, deliberately.** A waiter suspended here resumes when
/// a slot frees, and nothing in Zap cancels a rasterisation — stale work is
/// discarded by generation checks at the call site, after it completes, rather than
/// by cancelling it. A `withTaskCancellationHandler` would add a path that has no
/// caller and can't be tested from one.
actor SVGRenderGate {

    /// The one every rasterisation goes through.
    static let shared = SVGRenderGate(limit: 2)

    let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// How many renders hold a slot right now. For tests.
    var activeCount: Int { active }

    /// How many are queued behind them. For tests — the hand-off in `release` is
    /// only exercised if a waiter has actually suspended, and a test that guesses
    /// at that with a sleep is testing the other path half the time.
    var waitingCount: Int { waiting.count }

    /// Waits until a slot is free, then takes it. Every `acquire` must be paired
    /// with exactly one `release`.
    func acquire() async {
        guard active >= limit else {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    /// Gives a slot back, handing it straight to whoever has been waiting longest.
    ///
    /// The hand-off leaves `active` alone on purpose: the slot never becomes free,
    /// it changes owner. Decrementing and letting the waiter re-`acquire` would open
    /// a window for a newly arriving caller to take it first, which over a long
    /// browse is how a queue starves.
    func release() {
        if waiting.isEmpty {
            active = max(0, active - 1)
        } else {
            waiting.removeFirst().resume()
        }
    }
}

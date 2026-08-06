import Foundation

/// Tracks most-recently-used (MRU) ordering of applications.
///
/// Entries are keyed the way the shared icon store keys overrides (`IconEntryKey`):
/// by bundle path when known, bundle identifier otherwise — `AppInfo.mruKey`.
/// The identifier alone is not enough. Site-specific-browser wrappers all
/// report the browser's identifier, so keying on it gave every Chrome wrapper
/// one shared recency slot: using any of them dragged all of them forward,
/// ordered among themselves by process-table order instead of by actual use.
///
/// Pure logic with no system dependencies so it can be unit tested.
final class MRUTracker {

    /// MRU keys, most-recently-used first. An order persisted before keys were
    /// path-first holds bare identifiers; `ordered(_:)` still honours those as
    /// fallbacks, so nothing needed migrating (the same trick `IconEntryKey`
    /// plays with `legacyKey`).
    private(set) var order: [String]

    /// Creates a tracker, optionally seeded with the order persisted by a previous
    /// session (most-recently-used first). There is no API for the system's own MRU
    /// order, so the last session's order is the best available prior on a cold
    /// launch; live activations then correct it.
    init(order: [String] = []) {
        self.order = order
    }

    /// Records that an app was just activated, moving it to the front.
    func recordActivation(key: String) {
        order.removeAll { $0 == key }
        order.insert(key, at: 0)
    }

    /// Returns `apps` sorted by MRU order. An app not found under its key is
    /// looked up by bundle identifier, so a pre-path-first order still ranks it —
    /// wrappers sharing an identifier share that fallback rank and keep their
    /// relative input order until each is first activated. Apps found under
    /// neither key are placed after all known apps, in their input order.
    func ordered(_ apps: [AppInfo]) -> [AppInfo] {
        let rank = Dictionary(
            order.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Rank each app once up front: `mruKey` standardises a URL, which the
        // comparator must not re-do O(n log n) times on the ⌘-Tab path.
        return apps.enumerated()
            .map { (offset: $0.offset, app: $0.element,
                    rank: rank[$0.element.mruKey] ?? rank[$0.element.bundleIdentifier]) }
            .sorted { lhs, rhs in
                switch (lhs.rank, rhs.rank) {
                case let (l?, r?): return l == r ? lhs.offset < rhs.offset : l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.offset < rhs.offset
                }
            }
            .map(\.app)
    }
}

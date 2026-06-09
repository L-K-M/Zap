import Foundation

/// Tracks most-recently-used (MRU) ordering of applications by bundle identifier.
///
/// Pure logic with no system dependencies so it can be unit tested.
final class MRUTracker {

    /// Bundle identifiers, most-recently-used first.
    private(set) var order: [String]

    /// Creates a tracker, optionally seeded with the order persisted by a previous
    /// session (most-recently-used first). There is no API for the system's own MRU
    /// order, so the last session's order is the best available prior on a cold
    /// launch; live activations then correct it.
    init(order: [String] = []) {
        self.order = order
    }

    /// Records that an app was just activated, moving it to the front.
    func recordActivation(bundleID: String) {
        order.removeAll { $0 == bundleID }
        order.insert(bundleID, at: 0)
    }

    /// Returns `apps` sorted by MRU order. Apps not yet seen keep their relative
    /// input order and are placed after all known apps.
    func ordered(_ apps: [AppInfo]) -> [AppInfo] {
        let rank = Dictionary(
            order.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return apps.enumerated().sorted { lhs, rhs in
            let l = rank[lhs.element.bundleIdentifier]
            let r = rank[rhs.element.bundleIdentifier]
            switch (l, r) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }
        .map(\.element)
    }
}

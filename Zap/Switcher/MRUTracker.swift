import Foundation

/// Tracks most-recently-used (MRU) ordering of applications by bundle identifier.
///
/// Pure logic with no system dependencies so it can be unit tested.
final class MRUTracker {

    /// Bundle identifiers, most-recently-used first.
    private(set) var order: [String] = []

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

import Foundation

/// A short-lived cache of the process ids owning windows on a display.
///
/// The scoped app list needs those pids, and getting them costs a system-wide
/// Quartz window-list copy plus two SkyLight Space queries — expensive enough
/// that a ⌘-Tab *burst* would re-run all of it on every press, inside the
/// event-tap callback where the whole budget is a few milliseconds (see
/// `SwitcherController.appList(for:)` and ANALYSIS.md P1). Answers older than
/// `ttl` are recomputed, so a display's app set changing (a window dragged
/// across screens, an app launched) is picked up within the TTL rather than
/// never.
///
/// Deterministic under test: the clock is injected into every call, in the same
/// style as `LRUImageCache`.
struct DisplayPIDCache {

    /// How long one answer stays valid. A quarter-second covers a whole ⌘-Tab
    /// burst while keeping the scoped list comfortably fresh between bursts.
    static let defaultTTL: TimeInterval = 0.25

    private struct Entry {
        let pids: Set<pid_t>
        let timestamp: TimeInterval
    }

    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = DisplayPIDCache.defaultTTL) {
        self.ttl = max(0, ttl)
    }

    /// The cached pids for `displayID`, or `compute()` (then cached) on a miss,
    /// once the entry is older than the TTL, or always when the TTL is zero
    /// (which disables caching entirely). A computed empty set is cached
    /// like any other answer: the scoped-list fallback to the full list treats
    /// "nothing on this display" the same either way.
    mutating func pids(for displayID: String, now: TimeInterval,
                       compute: () -> Set<pid_t>) -> Set<pid_t> {
        if ttl > 0, let entry = entries[displayID], now - entry.timestamp <= ttl {
            return entry.pids
        }

        let pids = compute()
        entries[displayID] = Entry(pids: pids, timestamp: now)
        return pids
    }
}

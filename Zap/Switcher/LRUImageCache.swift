import AppKit
import CoreGraphics

/// A small fixed-capacity, time-bounded cache of window thumbnails keyed by
/// `CGWindowID`.
///
/// - **LRU eviction:** once `capacity` is exceeded the least-recently-used entry
///   is dropped, keeping memory bounded no matter how many windows are seen.
/// - **TTL:** entries older than `maxAge` are treated as misses so a captured
///   preview can't grow stale while a window keeps changing.
///
/// The current time is injected into every mutating call rather than read from a
/// global clock, so the eviction/expiry logic is deterministic under test.
struct LRUImageCache {

    let capacity: Int
    let maxAge: TimeInterval

    private struct Entry {
        let image: NSImage
        let timestamp: TimeInterval
    }

    /// Keys ordered least- to most-recently used (most recent at the end).
    private var order: [CGWindowID] = []
    private var store: [CGWindowID: Entry] = [:]

    init(capacity: Int, maxAge: TimeInterval) {
        self.capacity = max(1, capacity)
        self.maxAge = maxAge
    }

    var count: Int { store.count }

    /// Returns the cached image for `key`, or `nil` when absent or expired. A hit
    /// promotes the key to most-recently-used; an expired entry is evicted.
    mutating func value(for key: CGWindowID, now: TimeInterval) -> NSImage? {
        guard let entry = store[key] else { return nil }
        guard now - entry.timestamp <= maxAge else {
            remove(key)
            return nil
        }
        promote(key)
        return entry.image
    }

    /// Inserts (or refreshes) `image` for `key`, evicting the least-recently-used
    /// entry if the cache is over capacity.
    mutating func insert(_ image: NSImage, for key: CGWindowID, now: TimeInterval) {
        store[key] = Entry(image: image, timestamp: now)
        promote(key)
        while order.count > capacity, let oldest = order.first {
            remove(oldest)
        }
    }

    mutating func remove(_ key: CGWindowID) {
        store[key] = nil
        order.removeAll { $0 == key }
    }

    mutating func removeAll() {
        store.removeAll()
        order.removeAll()
    }

    private mutating func promote(_ key: CGWindowID) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}

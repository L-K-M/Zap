import XCTest
import AppKit
@testable import Zap

final class LRUImageCacheTests: XCTestCase {

    private func image() -> NSImage {
        NSImage(size: NSSize(width: 1, height: 1))
    }

    func testStoresAndRetrieves() {
        var cache = LRUImageCache(capacity: 4, maxAge: 100)
        let img = image()
        cache.insert(img, for: 1, now: 0)
        XCTAssertTrue(cache.value(for: 1, now: 1) === img)
        XCTAssertNil(cache.value(for: 2, now: 1))
    }

    func testEvictsLeastRecentlyUsedOverCapacity() {
        var cache = LRUImageCache(capacity: 2, maxAge: 100)
        cache.insert(image(), for: 1, now: 0)
        cache.insert(image(), for: 2, now: 0)
        // Touch key 1 so key 2 becomes least-recently-used.
        _ = cache.value(for: 1, now: 1)
        cache.insert(image(), for: 3, now: 2)

        XCTAssertNotNil(cache.value(for: 1, now: 3))
        XCTAssertNil(cache.value(for: 2, now: 3), "LRU entry should have been evicted")
        XCTAssertNotNil(cache.value(for: 3, now: 3))
        XCTAssertEqual(cache.count, 2)
    }

    func testExpiresStaleEntries() {
        var cache = LRUImageCache(capacity: 4, maxAge: 5)
        cache.insert(image(), for: 1, now: 0)
        XCTAssertNotNil(cache.value(for: 1, now: 5), "Entry at exactly maxAge is still valid")
        XCTAssertNil(cache.value(for: 1, now: 6), "Entry past maxAge should be a miss")
        XCTAssertEqual(cache.count, 0, "Expired entry should be evicted on access")
    }

    func testReinsertRefreshesTimestampAndRecency() {
        var cache = LRUImageCache(capacity: 2, maxAge: 10)
        cache.insert(image(), for: 1, now: 0)
        cache.insert(image(), for: 2, now: 0)
        // Re-insert key 1 later: refreshes its age and marks it most-recent.
        cache.insert(image(), for: 1, now: 8)
        cache.insert(image(), for: 3, now: 9) // evicts LRU, which is now key 2

        XCTAssertNotNil(cache.value(for: 1, now: 9))
        XCTAssertNil(cache.value(for: 2, now: 9))
        XCTAssertNotNil(cache.value(for: 3, now: 9))
    }

    func testRemoveAllClears() {
        var cache = LRUImageCache(capacity: 4, maxAge: 100)
        cache.insert(image(), for: 1, now: 0)
        cache.insert(image(), for: 2, now: 0)
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertNil(cache.value(for: 1, now: 1))
    }
}

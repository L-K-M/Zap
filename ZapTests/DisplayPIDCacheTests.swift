import XCTest
@testable import Zap

/// The short-lived display-scope cache (see `DisplayPIDCache`): a ⌘-Tab burst
/// must not re-run the system-wide window queries on every press, but a stale
/// answer must never outlive its TTL.
final class DisplayPIDCacheTests: XCTestCase {

    func testComputeIsCalledOnceWithinTTL() {
        var cache = DisplayPIDCache(ttl: 0.25)
        var calls = 0
        func compute() -> Set<pid_t> { calls += 1; return [1, 2] }

        XCTAssertEqual(cache.pids(for: "A", now: 100, compute: compute), [1, 2])
        XCTAssertEqual(cache.pids(for: "A", now: 100.2, compute: compute), [1, 2])
        XCTAssertEqual(cache.pids(for: "A", now: 100.25, compute: compute), [1, 2])
        XCTAssertEqual(calls, 1)
    }

    func testComputeRunsAgainAfterTTL() {
        var cache = DisplayPIDCache(ttl: 0.25)
        var calls = 0
        func compute() -> Set<pid_t> { calls += 1; return [pid_t(calls)] }

        XCTAssertEqual(cache.pids(for: "A", now: 100, compute: compute), [1])
        XCTAssertEqual(cache.pids(for: "A", now: 100.3, compute: compute), [2])
        XCTAssertEqual(calls, 2)
    }

    func testDisplaysAreCachedIndependently() {
        var cache = DisplayPIDCache(ttl: 0.25)
        var calls = 0
        func compute() -> Set<pid_t> { calls += 1; return [pid_t(calls)] }

        XCTAssertEqual(cache.pids(for: "A", now: 100, compute: compute), [1])
        XCTAssertEqual(cache.pids(for: "B", now: 100, compute: compute), [2])
        XCTAssertEqual(cache.pids(for: "A", now: 100, compute: compute), [1])
        XCTAssertEqual(calls, 2)
    }

    func testEmptyResultIsCachedLikeAnyOther() {
        var cache = DisplayPIDCache(ttl: 0.25)
        var calls = 0
        func compute() -> Set<pid_t> { calls += 1; return [] }

        XCTAssertEqual(cache.pids(for: "A", now: 100, compute: compute), [])
        XCTAssertEqual(cache.pids(for: "A", now: 100.1, compute: compute), [])
        XCTAssertEqual(calls, 1)
    }

    func testZeroTTLNeverServesACachedAnswer() {
        var cache = DisplayPIDCache(ttl: 0)
        var calls = 0
        func compute() -> Set<pid_t> { calls += 1; return [1] }

        _ = cache.pids(for: "A", now: 100, compute: compute)
        _ = cache.pids(for: "A", now: 100, compute: compute)
        XCTAssertEqual(calls, 2)
    }
}

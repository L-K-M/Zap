import XCTest
@testable import Zap

/// The MRU persistence throttle (see `AppListProvider.shouldPersist`): every
/// system-wide app activation updates the order, but writing it out on each one
/// turns one of the most frequent events on the machine into a UserDefaults
/// write. The order is flushed at most once per interval (and at teardown).
final class MRUPersistThrottleTests: XCTestCase {

    private let interval: TimeInterval = 2

    func testFirstWriteAlwaysPersists() {
        XCTAssertTrue(AppListProvider.shouldPersist(now: 100, lastPersistAt: nil,
                                                    interval: interval))
    }

    func testWriteWithinIntervalIsSkipped() {
        XCTAssertFalse(AppListProvider.shouldPersist(now: 101.5, lastPersistAt: 100,
                                                     interval: interval))
    }

    func testWriteAtIntervalIsAllowed() {
        XCTAssertTrue(AppListProvider.shouldPersist(now: 102, lastPersistAt: 100,
                                                    interval: interval))
    }

    func testWriteAfterIntervalIsAllowed() {
        XCTAssertTrue(AppListProvider.shouldPersist(now: 130, lastPersistAt: 100,
                                                    interval: interval))
    }

    func testZeroIntervalAlwaysPersists() {
        XCTAssertTrue(AppListProvider.shouldPersist(now: 100, lastPersistAt: 100,
                                                    interval: 0))
    }
}

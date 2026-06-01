import XCTest
@testable import Zap

final class MRUTrackerTests: XCTestCase {

    private func app(_ id: String, pid: pid_t = 0) -> AppInfo {
        AppInfo(bundleIdentifier: id, name: id, processIdentifier: pid)
    }

    func testMostRecentMovesToFront() {
        let tracker = MRUTracker()
        tracker.recordActivation(bundleID: "a")
        tracker.recordActivation(bundleID: "b")
        tracker.recordActivation(bundleID: "c")
        XCTAssertEqual(tracker.order, ["c", "b", "a"])
    }

    func testReactivationDeduplicates() {
        let tracker = MRUTracker()
        tracker.recordActivation(bundleID: "a")
        tracker.recordActivation(bundleID: "b")
        tracker.recordActivation(bundleID: "a")
        XCTAssertEqual(tracker.order, ["a", "b"])
    }

    func testOrderedSortsKnownAppsByRecency() {
        let tracker = MRUTracker()
        tracker.recordActivation(bundleID: "a")
        tracker.recordActivation(bundleID: "b")
        tracker.recordActivation(bundleID: "c") // order: c, b, a

        let input = [app("a"), app("b"), app("c")]
        let result = tracker.ordered(input).map(\.bundleIdentifier)
        XCTAssertEqual(result, ["c", "b", "a"])
    }

    func testUnknownAppsKeepInputOrderAfterKnown() {
        let tracker = MRUTracker()
        tracker.recordActivation(bundleID: "b") // only b is known

        let input = [app("a"), app("b"), app("c")]
        let result = tracker.ordered(input).map(\.bundleIdentifier)
        XCTAssertEqual(result, ["b", "a", "c"])
    }

    func testSecondItemIsPreviousAppForToggle() {
        // The frontmost (most-recent) app is index 0; index 1 is the previous app
        // that a single ⌘-Tab should switch to.
        let tracker = MRUTracker()
        tracker.recordActivation(bundleID: "previous")
        tracker.recordActivation(bundleID: "current")

        let ordered = tracker.ordered([app("current"), app("previous")])
        XCTAssertEqual(ordered[1].bundleIdentifier, "previous")
    }
}

import XCTest
@testable import Zap

final class MRUTrackerTests: XCTestCase {

    private func app(_ id: String, pid: pid_t = 0) -> AppInfo {
        AppInfo(bundleIdentifier: id, name: id, processIdentifier: pid)
    }

    /// A site-specific-browser wrapper: its own bundle on disk, the browser's
    /// bundle identifier. `mruKey` is then the path, not the identifier.
    private func wrapper(_ name: String, id: String = "com.google.Chrome") -> AppInfo {
        AppInfo(bundleIdentifier: id, name: name, processIdentifier: 0,
                bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    func testMostRecentMovesToFront() {
        let tracker = MRUTracker()
        tracker.recordActivation(key: "a")
        tracker.recordActivation(key: "b")
        tracker.recordActivation(key: "c")
        XCTAssertEqual(tracker.order, ["c", "b", "a"])
    }

    func testReactivationDeduplicates() {
        let tracker = MRUTracker()
        tracker.recordActivation(key: "a")
        tracker.recordActivation(key: "b")
        tracker.recordActivation(key: "a")
        XCTAssertEqual(tracker.order, ["a", "b"])
    }

    func testOrderedSortsKnownAppsByRecency() {
        let tracker = MRUTracker()
        tracker.recordActivation(key: "a")
        tracker.recordActivation(key: "b")
        tracker.recordActivation(key: "c") // order: c, b, a

        let input = [app("a"), app("b"), app("c")]
        let result = tracker.ordered(input).map(\.bundleIdentifier)
        XCTAssertEqual(result, ["c", "b", "a"])
    }

    func testUnknownAppsKeepInputOrderAfterKnown() {
        let tracker = MRUTracker()
        tracker.recordActivation(key: "b") // only b is known

        let input = [app("a"), app("b"), app("c")]
        let result = tracker.ordered(input).map(\.bundleIdentifier)
        XCTAssertEqual(result, ["b", "a", "c"])
    }

    func testSeededOrderIsRespected() {
        // A tracker seeded from a persisted order ranks known apps by it.
        let tracker = MRUTracker(order: ["b", "a"])
        let result = tracker.ordered([app("a"), app("b"), app("c")]).map(\.bundleIdentifier)
        XCTAssertEqual(result, ["b", "a", "c"])
    }

    func testActivationPromotesOverSeededOrder() {
        let tracker = MRUTracker(order: ["b", "a"])
        tracker.recordActivation(key: "a")
        XCTAssertEqual(tracker.order, ["a", "b"])
    }

    func testSecondItemIsPreviousAppForToggle() {
        // The frontmost (most-recent) app is index 0; index 1 is the previous app
        // that a single ⌘-Tab should switch to.
        let tracker = MRUTracker()
        tracker.recordActivation(key: "previous")
        tracker.recordActivation(key: "current")

        let ordered = tracker.ordered([app("current"), app("previous")])
        XCTAssertEqual(ordered[1].bundleIdentifier, "previous")
    }

    func testWrappersSharingAnIdentifierOrderIndependently() {
        // Three wrappers, one identifier: recency must follow the individual
        // app. Keyed by identifier they shared one slot and came out in
        // process-table order.
        let tracker = MRUTracker()
        let claude = wrapper("Claude ★")
        let nomad = wrapper("CodeNomad")
        let nomadDev = wrapper("CodeNomad Dev")

        tracker.recordActivation(key: nomadDev.mruKey)
        tracker.recordActivation(key: claude.mruKey)
        tracker.recordActivation(key: nomad.mruKey)

        let result = tracker.ordered([claude, nomadDev, nomad]).map(\.name)
        XCTAssertEqual(result, ["CodeNomad", "Claude ★", "CodeNomad Dev"])
    }

    func testActivatingOneWrapperLeavesItsSiblingsBehind() {
        // Using one wrapper must not drag its never-activated sibling past
        // apps that really were used more recently.
        let tracker = MRUTracker()
        let claude = wrapper("Claude ★")
        let nomad = wrapper("CodeNomad")
        tracker.recordActivation(key: "com.apple.Safari")
        tracker.recordActivation(key: nomad.mruKey)

        let result = tracker.ordered([claude, app("com.apple.Safari"), nomad]).map(\.name)
        XCTAssertEqual(result, ["CodeNomad", "com.apple.Safari", "Claude ★"])
    }

    func testIdentifierEntryFromEarlierVersionRanksWrappersUntilActivated() {
        // An order persisted before keys were path-first holds bare identifiers.
        // Wrappers fall back to that shared entry — keeping their input order —
        // until an activation gives each a path entry of its own.
        let tracker = MRUTracker(order: ["com.google.Chrome", "com.apple.Safari"])
        let claude = wrapper("Claude ★")
        let nomad = wrapper("CodeNomad")
        let safari = app("com.apple.Safari")

        XCTAssertEqual(tracker.ordered([safari, claude, nomad]).map(\.name),
                       ["Claude ★", "CodeNomad", "com.apple.Safari"])

        tracker.recordActivation(key: nomad.mruKey)
        XCTAssertEqual(tracker.ordered([safari, claude, nomad]).map(\.name),
                       ["CodeNomad", "Claude ★", "com.apple.Safari"])
    }
}

import XCTest
@testable import Zap

/// Pending-quit selection rules (mimo.md §1 / ANALYSIS.md B8).
///
/// A quit request is about the *app*, not the session that asked: its icon
/// stays dimmed and unselectable until the quit is verified, and that can
/// outlive the session. These rules keep the highlight off such apps both while
/// cycling and when a fresh session opens.
final class PendingQuitTests: XCTestCase {

    private let a = AppInfo(bundleIdentifier: "a", name: "A", processIdentifier: 1)
    private let b = AppInfo(bundleIdentifier: "b", name: "B", processIdentifier: 2)
    private let c = AppInfo(bundleIdentifier: "c", name: "C", processIdentifier: 3)

    // MARK: nextSelectableIndex

    func testSelectionSkipsQuittingApps() {
        let apps = [a, b, c]
        XCTAssertEqual(SwitcherController.nextSelectableIndex(in: apps, skipping: [2],
                                                              from: 0, forward: true), 2)
    }

    func testSelectionWrapsAroundSkippingQuittingApps() {
        let apps = [a, b, c]
        XCTAssertEqual(SwitcherController.nextSelectableIndex(in: apps, skipping: [3],
                                                              from: 2, forward: true), 0)
    }

    func testSelectionWalksBackward() {
        let apps = [a, b, c]
        XCTAssertEqual(SwitcherController.nextSelectableIndex(in: apps, skipping: [2],
                                                              from: 2, forward: false), 0)
    }

    func testNilWhenEveryAppIsQuitting() {
        let apps = [a, b]
        XCTAssertNil(SwitcherController.nextSelectableIndex(in: apps, skipping: [1, 2],
                                                            from: 0, forward: true))
    }

    func testNilForEmptyList() {
        XCTAssertNil(SwitcherController.nextSelectableIndex(in: [], skipping: [],
                                                            from: 0, forward: true))
    }

    // MARK: sessionOpeningSelection

    func testOpeningSelectionKeepsANonQuittingDefault() {
        let apps = [a, b, c]
        XCTAssertEqual(SwitcherController.sessionOpeningSelection(defaultIndex: 1,
                                                                  apps: apps,
                                                                  quittingPIDs: []), 1)
    }

    func testOpeningSelectionMovesOffAQuittingDefault() {
        // Pending-quit state outlives the session that requested it: a fresh
        // session must not open with the highlight on an app that can't be chosen.
        let apps = [a, b, c]
        XCTAssertEqual(SwitcherController.sessionOpeningSelection(defaultIndex: 0,
                                                                  apps: apps,
                                                                  quittingPIDs: [1]), 1)
    }

    func testOpeningSelectionSkipsEveryQuittingApp() {
        let apps = [a, b, c]
        XCTAssertEqual(SwitcherController.sessionOpeningSelection(defaultIndex: 0,
                                                                  apps: apps,
                                                                  quittingPIDs: [1, 2]), 2)
    }

    func testOpeningSelectionFallsBackToDefaultWhenAllAreQuitting() {
        // Nothing can be chosen; commit already refuses to activate a quitting
        // app, so keeping the requested index is harmless and keeps the rule
        // total.
        let apps = [a, b]
        XCTAssertEqual(SwitcherController.sessionOpeningSelection(defaultIndex: 0,
                                                                  apps: apps,
                                                                  quittingPIDs: [1, 2]), 0)
    }
}

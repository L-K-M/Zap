import XCTest
@testable import Zap

/// Tests the pure screen-scope + exclusion filter that decides which apps appear in
/// the switcher on a scoped display.
final class ScreenScopeFilterTests: XCTestCase {

    private func app(_ id: String, pid: pid_t) -> AppInfo {
        AppInfo(bundleIdentifier: id, name: id, processIdentifier: pid)
    }

    private lazy var apps = [app("a", pid: 1), app("b", pid: 2), app("c", pid: 3)]

    // MARK: Off

    func testOffIgnoresScreenAndAppliesExclusions() {
        let result = AppListProvider.scoped(apps, mode: .off,
                                            pidsOnScreen: [1],          // ignored when off
                                            excluding: ["b"])
        XCTAssertEqual(result.map(\.bundleIdentifier), ["a", "c"])
    }

    func testOffWithNoExclusionsKeepsEverything() {
        let result = AppListProvider.scoped(apps, mode: .off, pidsOnScreen: [], excluding: [])
        XCTAssertEqual(result.map(\.bundleIdentifier), ["a", "b", "c"])
    }

    // MARK: Scoped, respecting exclusions

    func testRespectingExclusionsKeepsOnlyOnScreenMinusExcluded() {
        let result = AppListProvider.scoped(apps, mode: .scopedRespectingExclusions,
                                            pidsOnScreen: [1, 2],
                                            excluding: ["b"])
        // b is on-screen but excluded → dropped; c is not on-screen → dropped.
        XCTAssertEqual(result.map(\.bundleIdentifier), ["a"])
    }

    func testRespectingExclusionsWithEmptyScreenIsEmpty() {
        let result = AppListProvider.scoped(apps, mode: .scopedRespectingExclusions,
                                            pidsOnScreen: [], excluding: [])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: Scoped, ignoring exclusions

    func testIgnoringExclusionsKeepsOnScreenEvenWhenExcluded() {
        let result = AppListProvider.scoped(apps, mode: .scopedIgnoringExclusions,
                                            pidsOnScreen: [1, 2],
                                            excluding: ["b"])
        // b is excluded but its window is on this display → still shown.
        XCTAssertEqual(result.map(\.bundleIdentifier), ["a", "b"])
    }

    func testIgnoringExclusionsStillFiltersByScreen() {
        let result = AppListProvider.scoped(apps, mode: .scopedIgnoringExclusions,
                                            pidsOnScreen: [3], excluding: ["a", "b", "c"])
        XCTAssertEqual(result.map(\.bundleIdentifier), ["c"])
    }

    // MARK: Order

    func testScopingPreservesInputOrder() {
        let input = [app("a", pid: 1), app("b", pid: 2), app("c", pid: 3), app("d", pid: 4)]
        let result = AppListProvider.scoped(input, mode: .scopedRespectingExclusions,
                                            pidsOnScreen: [4, 1, 3], excluding: [])
        XCTAssertEqual(result.map(\.bundleIdentifier), ["a", "c", "d"])
    }
}

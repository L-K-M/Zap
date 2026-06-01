import XCTest
@testable import Zap

final class ExclusionFilterTests: XCTestCase {

    private func app(_ id: String) -> AppInfo {
        AppInfo(bundleIdentifier: id, name: id, processIdentifier: 0)
    }

    func testExcludedAppsAreRemoved() {
        let input = [app("a"), app("b"), app("c")]
        let result = AppListProvider.filtered(input, excluding: ["b"])
        XCTAssertEqual(result.map(\.bundleIdentifier), ["a", "c"])
    }

    func testEmptyExclusionKeepsEverything() {
        let input = [app("a"), app("b")]
        let result = AppListProvider.filtered(input, excluding: [])
        XCTAssertEqual(result.map(\.bundleIdentifier), ["a", "b"])
    }

    func testExcludingAllYieldsEmpty() {
        let input = [app("a"), app("b")]
        let result = AppListProvider.filtered(input, excluding: ["a", "b"])
        XCTAssertTrue(result.isEmpty)
    }

    func testFilterPreservesOrder() {
        let input = [app("a"), app("b"), app("c"), app("d")]
        let result = AppListProvider.filtered(input, excluding: ["c"])
        XCTAssertEqual(result.map(\.bundleIdentifier), ["a", "b", "d"])
    }
}

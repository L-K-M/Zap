import XCTest
@testable import Zap

final class SwitcherSelectionTests: XCTestCase {

    private func app(_ id: String) -> AppInfo {
        AppInfo(bundleIdentifier: id, name: id, processIdentifier: 0)
    }

    func testEmptyListSelectsZero() {
        XCTAssertEqual(
            SwitcherController.defaultSelection(forward: true, apps: [], frontmostBundleID: nil),
            0
        )
    }

    func testSingleAppSelectsZero() {
        let apps = [app("a")]
        XCTAssertEqual(
            SwitcherController.defaultSelection(forward: true, apps: apps, frontmostBundleID: "a"),
            0
        )
    }

    func testForwardWithSurvivingFrontmostPicksPreviousApp() {
        // Frontmost (a) is at index 0, so the previous app is index 1.
        let apps = [app("a"), app("b"), app("c")]
        XCTAssertEqual(
            SwitcherController.defaultSelection(forward: true, apps: apps, frontmostBundleID: "a"),
            1
        )
    }

    func testForwardWithExcludedFrontmostPicksIndexZero() {
        // Frontmost app was filtered out, so index 0 is already the previous app.
        let apps = [app("b"), app("c")]
        XCTAssertEqual(
            SwitcherController.defaultSelection(forward: true, apps: apps, frontmostBundleID: "a"),
            0
        )
    }

    func testForwardWithNilFrontmostPicksPreviousApp() {
        // A nil frontmost means Zap itself is frontmost (Settings / update alert).
        // The MRU list skips Zap's activations, so index 0 (b) is still the app
        // the user is effectively in; selecting it would commit the current app
        // and read as a dead switcher. The real previous app is index 1.
        let apps = [app("b"), app("c")]
        XCTAssertEqual(
            SwitcherController.defaultSelection(forward: true, apps: apps, frontmostBundleID: nil),
            1
        )
    }

    func testForwardWithNilFrontmostAndSingleAppSelectsZero() {
        let apps = [app("a")]
        XCTAssertEqual(
            SwitcherController.defaultSelection(forward: true, apps: apps, frontmostBundleID: nil),
            0
        )
    }

    func testReverseSelectsLastIndex() {
        let apps = [app("a"), app("b"), app("c")]
        XCTAssertEqual(
            SwitcherController.defaultSelection(forward: false, apps: apps, frontmostBundleID: "a"),
            2
        )
    }
}

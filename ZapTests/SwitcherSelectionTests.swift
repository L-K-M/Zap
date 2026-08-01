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

    func testForwardWithLeftoverZapActivationPicksPreviousApp() {
        // A nil frontmost with no window of Zap's on screen is activation left over
        // from a closed Settings window or a dismissed update alert. The MRU list
        // skips Zap's activations, so index 0 (b) is still the app the user is
        // looking at; selecting it would commit the current app and read as a dead
        // switcher. The real previous app is index 1.
        let apps = [app("b"), app("c")]
        XCTAssertEqual(
            SwitcherController.defaultSelection(forward: true, apps: apps, frontmostBundleID: nil,
                                                zapIsShowingAWindow: false),
            1
        )
    }

    func testForwardWithZapsOwnWindowOnScreenPicksIndexZero() {
        // Settings is open and frontmost, so the user really is in Zap. Zap keeps
        // itself out of its own list, which makes index 0 (b) the most recent app —
        // index 1 would skip straight past it.
        let apps = [app("b"), app("c")]
        XCTAssertEqual(
            SwitcherController.defaultSelection(forward: true, apps: apps, frontmostBundleID: nil,
                                                zapIsShowingAWindow: true),
            0
        )
    }

    func testForwardWithNilFrontmostAndSingleAppSelectsZero() {
        let apps = [app("a")]
        for showingAWindow in [true, false] {
            XCTAssertEqual(
                SwitcherController.defaultSelection(forward: true, apps: apps, frontmostBundleID: nil,
                                                    zapIsShowingAWindow: showingAWindow),
                0
            )
        }
    }

    func testZapWindowFlagOnlySplitsTheNilFrontmostCase() {
        // The flag exists to tell leftover activation apart from Settings being on
        // screen — both of which read as a nil frontmost. A real frontmost app
        // answers the question on its own, so the flag must not be consulted.
        let apps = [app("b"), app("c")]
        for showingAWindow in [true, false] {
            XCTAssertEqual(
                SwitcherController.defaultSelection(forward: true, apps: apps, frontmostBundleID: "b",
                                                    zapIsShowingAWindow: showingAWindow),
                1
            )
            XCTAssertEqual(
                SwitcherController.defaultSelection(forward: true, apps: apps, frontmostBundleID: "a",
                                                    zapIsShowingAWindow: showingAWindow),
                0
            )
        }
    }

    func testReverseSelectsLastIndex() {
        let apps = [app("a"), app("b"), app("c")]
        XCTAssertEqual(
            SwitcherController.defaultSelection(forward: false, apps: apps, frontmostBundleID: "a"),
            2
        )
    }
}

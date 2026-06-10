import XCTest
@testable import Zap

final class ShortcutKeyRoutingTests: XCTestCase {

    func testWindowFocusKeepsNativeShortcuts() {
        // While a window-list row is focused the user is navigating, not
        // searching — all three keys act immediately, like the native switcher.
        XCTAssertEqual(SwitcherController.shortcutRouting(for: .quit, windowFocused: true), .act)
        XCTAssertEqual(SwitcherController.shortcutRouting(for: .hide, windowFocused: true), .act)
        XCTAssertEqual(SwitcherController.shortcutRouting(for: .closeWindow, windowFocused: true), .act)
    }

    func testCloseWindowIsAPlainLetterOnTheAppRow() {
        // Close-window needs a focused window; with none, "w" must reach the
        // search query so names like "Wave" are typeable.
        XCTAssertEqual(SwitcherController.shortcutRouting(for: .closeWindow, windowFocused: false), .type)
    }

    func testQuitAndHideTypeButArmAHoldOnTheAppRow() {
        // A tap types (so "QuickTime" and "Hammerspoon" are searchable); only a
        // hold performs the destructive/native action.
        XCTAssertEqual(SwitcherController.shortcutRouting(for: .quit, windowFocused: false), .typeAndArmHold)
        XCTAssertEqual(SwitcherController.shortcutRouting(for: .hide, windowFocused: false), .typeAndArmHold)
    }
}

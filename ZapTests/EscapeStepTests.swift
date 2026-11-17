import XCTest
@testable import Zap

/// Esc undoes one layer at a time, innermost first, so backing out of a window
/// doesn't throw away the whole switch.
final class EscapeStepTests: XCTestCase {

    func testAQueryIsClearedFirst() {
        XCTAssertEqual(SwitcherController.escapeStep(hasQuery: true, windowFocused: false), .clearQuery)
        XCTAssertEqual(SwitcherController.escapeStep(hasQuery: true, windowFocused: true), .clearQuery)
    }

    func testAFocusedWindowReturnsToTheAppRow() {
        XCTAssertEqual(SwitcherController.escapeStep(hasQuery: false, windowFocused: true), .unfocusWindow)
    }

    func testOnTheAppRowEscCancels() {
        XCTAssertEqual(SwitcherController.escapeStep(hasQuery: false, windowFocused: false), .cancelSession)
    }

    /// ↓ shows the windows straight away instead of waiting out the dwell, but
    /// only when the list is on and nothing is shown yet.
    func testDownRevealsWindowsOnlyBeforeTheListIsShown() {
        XCTAssertTrue(SwitcherController.revealsWindowsImmediately(
            direction: .down, windowsShown: false, windowListEnabled: true))
        XCTAssertFalse(SwitcherController.revealsWindowsImmediately(
            direction: .down, windowsShown: true, windowListEnabled: true))
        XCTAssertFalse(SwitcherController.revealsWindowsImmediately(
            direction: .down, windowsShown: false, windowListEnabled: false))
        for direction in [WindowNavDirection.up, .left, .right] {
            XCTAssertFalse(SwitcherController.revealsWindowsImmediately(
                direction: direction, windowsShown: false, windowListEnabled: true))
        }
    }
}

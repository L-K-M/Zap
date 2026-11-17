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
    /// only when the list is on, nothing is shown yet, and the dwell hasn't
    /// already looked (so ↓ never repeats a lookup that found nothing).
    func testDownRevealsWindowsOnlyWhileTheDwellIsPending() {
        func reveals(_ direction: WindowNavDirection = .down, shown: Bool = false,
                     pending: Bool = true, enabled: Bool = true) -> Bool {
            SwitcherController.revealsWindowsImmediately(
                direction: direction, windowsShown: shown,
                dwellPending: pending, windowListEnabled: enabled)
        }

        XCTAssertTrue(reveals())
        XCTAssertFalse(reveals(shown: true))
        XCTAssertFalse(reveals(pending: false), "the dwell already looked")
        XCTAssertFalse(reveals(enabled: false))
        for direction in [WindowNavDirection.up, .left, .right] {
            XCTAssertFalse(reveals(direction))
        }
    }
}

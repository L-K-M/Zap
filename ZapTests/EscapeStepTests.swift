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
}

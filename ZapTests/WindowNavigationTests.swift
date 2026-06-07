import XCTest
@testable import Zap

/// Tests the pure arrow-key navigation rule for the revealed windows, in both the
/// single-column list and the multi-column preview grid. `nil` means the app row
/// (above the windows) is focused.
final class WindowNavigationTests: XCTestCase {

    private func next(from current: Int?, _ direction: WindowNavDirection,
                      count: Int, columns: Int) -> Int? {
        SwitcherController.nextWindowSelection(from: current, direction: direction,
                                               count: count, columns: columns)
    }

    // MARK: List (single column) — reproduces the original behavior

    func testListDownAdvancesAndEntersFromAppRow() {
        XCTAssertEqual(next(from: nil, .down, count: 5, columns: 1), 0)
        XCTAssertEqual(next(from: 0, .down, count: 5, columns: 1), 1)
        XCTAssertEqual(next(from: 3, .down, count: 5, columns: 1), 4)
    }

    func testListDownClampsAtLast() {
        XCTAssertEqual(next(from: 4, .down, count: 5, columns: 1), 4)
    }

    func testListUpStepsBackAndReturnsToAppRow() {
        XCTAssertEqual(next(from: 2, .up, count: 5, columns: 1), 1)
        XCTAssertEqual(next(from: 0, .up, count: 5, columns: 1), nil)   // back to app row
        XCTAssertEqual(next(from: nil, .up, count: 5, columns: 1), nil)
    }

    func testListLeftRightAreNoOps() {
        XCTAssertEqual(next(from: 2, .left, count: 5, columns: 1), 2)
        XCTAssertEqual(next(from: 2, .right, count: 5, columns: 1), 2)
        XCTAssertEqual(next(from: nil, .right, count: 5, columns: 1), nil)
    }

    // MARK: Grid — 3 columns, 8 windows  ⇒  rows [0,1,2] [3,4,5] [6,7]

    func testGridEntersGridFromAppRowOnDown() {
        XCTAssertEqual(next(from: nil, .down, count: 8, columns: 3), 0)
        XCTAssertEqual(next(from: nil, .up, count: 8, columns: 3), nil)
    }

    func testGridMovesByRowAndColumnFromMiddle() {
        XCTAssertEqual(next(from: 4, .down, count: 8, columns: 3), 7)
        XCTAssertEqual(next(from: 4, .up, count: 8, columns: 3), 1)
        XCTAssertEqual(next(from: 4, .left, count: 8, columns: 3), 3)
        XCTAssertEqual(next(from: 4, .right, count: 8, columns: 3), 5)
    }

    func testGridUpFromTopRowReturnsToAppRow() {
        XCTAssertEqual(next(from: 2, .up, count: 8, columns: 3), nil)
        XCTAssertEqual(next(from: 0, .up, count: 8, columns: 3), nil)
    }

    func testGridRightStopsAtRowEnd() {
        XCTAssertEqual(next(from: 2, .right, count: 8, columns: 3), 2)   // rightmost of row 0
    }

    func testGridLeftStopsAtRowStart() {
        XCTAssertEqual(next(from: 3, .left, count: 8, columns: 3), 3)    // leftmost of row 1
    }

    func testGridDownIntoShortLastRowClampsToNearest() {
        // Below window 5 (row 1, col 2) the last row has no col-2 cell ⇒ clamp to last.
        XCTAssertEqual(next(from: 5, .down, count: 8, columns: 3), 7)
    }

    func testGridDownFromLastRowStaysPut() {
        XCTAssertEqual(next(from: 6, .down, count: 8, columns: 3), 6)
        XCTAssertEqual(next(from: 7, .down, count: 8, columns: 3), 7)
    }

    func testGridRightAtEndOfShortLastRowStaysPut() {
        // Window 7 is the last; there's no col-2 cell in the short last row.
        XCTAssertEqual(next(from: 7, .right, count: 8, columns: 3), 7)
    }

    // MARK: Grid — 2 columns, 4 windows  ⇒  rows [0,1] [2,3]

    func testTwoColumnGridVerticalMoves() {
        XCTAssertEqual(next(from: 0, .down, count: 4, columns: 2), 2)
        XCTAssertEqual(next(from: 1, .down, count: 4, columns: 2), 3)
        XCTAssertEqual(next(from: 2, .up, count: 4, columns: 2), 0)
        XCTAssertEqual(next(from: 3, .up, count: 4, columns: 2), 1)
    }

    func testEmptyWindowsHasNoSelection() {
        XCTAssertEqual(next(from: nil, .down, count: 0, columns: 1), nil)
        XCTAssertEqual(next(from: 0, .down, count: 0, columns: 3), nil)
    }
}

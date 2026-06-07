import XCTest
@testable import Zap

/// Tests for the window-preview grid geometry: how N windows tile into columns and
/// rows within an available width, and the resulting block size.
///
/// Most cases use 132×104 cells with 8pt spacing (so each column step is 140pt),
/// matching `WindowGridMetrics`.
final class WindowGridGeometryTests: XCTestCase {

    private let accuracy: CGFloat = 1e-6

    private func grid(count: Int, width: CGFloat) -> WindowGridGeometry {
        WindowGridGeometry(count: count, availableWidth: width,
                           cellWidth: 132, cellHeight: 104, spacing: 8)
    }

    // MARK: Column count (square-ish, width-permitting)

    func testColumnsAreRoughlySquareWhenWidthAllows() {
        // ceil(sqrt(n)) when there's ample width.
        XCTAssertEqual(grid(count: 1, width: 2000).columns, 1)
        XCTAssertEqual(grid(count: 2, width: 2000).columns, 2)
        XCTAssertEqual(grid(count: 3, width: 2000).columns, 2)
        XCTAssertEqual(grid(count: 4, width: 2000).columns, 2)
        XCTAssertEqual(grid(count: 5, width: 2000).columns, 3)
        XCTAssertEqual(grid(count: 9, width: 2000).columns, 3)
        XCTAssertEqual(grid(count: 10, width: 2000).columns, 4)
    }

    func testColumnsCappedByAvailableWidth() {
        // 300pt fits two 140pt column steps, so a 9-window grid is forced to 2 cols.
        XCTAssertEqual(grid(count: 9, width: 300).columns, 2)
        // A very narrow panel still shows a single column rather than zero.
        XCTAssertEqual(grid(count: 9, width: 100).columns, 1)
    }

    func testColumnsNeverExceedCount() {
        XCTAssertEqual(grid(count: 1, width: 2000).columns, 1)
        XCTAssertEqual(grid(count: 2, width: 2000).columns, 2)
    }

    func testZeroWindowsHasNoColumnsOrRows() {
        let g = grid(count: 0, width: 2000)
        XCTAssertEqual(g.columns, 0)
        XCTAssertEqual(g.rows, 0)
        XCTAssertEqual(g.width, 0, accuracy: accuracy)
        XCTAssertEqual(g.height, 0, accuracy: accuracy)
    }

    /// An unset/unbounded available width must not trap when converted to a column
    /// count — it should behave as "as many as a square layout wants".
    func testUnboundedWidthIsSafe() {
        XCTAssertEqual(grid(count: 9, width: .greatestFiniteMagnitude).columns, 3)
        XCTAssertEqual(grid(count: 9, width: .infinity).columns, 3)
    }

    // MARK: Rows

    func testRowsWrapAroundColumns() {
        XCTAssertEqual(grid(count: 8, width: 2000).rows, 3)   // 3 cols ⇒ 3,3,2
        XCTAssertEqual(grid(count: 9, width: 2000).rows, 3)   // 3 cols ⇒ 3,3,3
        XCTAssertEqual(grid(count: 9, width: 300).rows, 5)    // 2 cols ⇒ 2,2,2,2,1
    }

    // MARK: Pixel size

    func testWidthAndHeightFromColumnsAndRows() {
        let g = grid(count: 5, width: 2000)                   // 3 cols, 2 rows
        XCTAssertEqual(g.width, 3 * 132 + 2 * 8, accuracy: accuracy)   // 412
        XCTAssertEqual(g.height, 2 * 104 + 1 * 8, accuracy: accuracy)  // 216
    }

    func testWidthNeverExceedsAvailableWidth() {
        // 9 windows in 300pt ⇒ 2 columns ⇒ 2*132 + 8 = 272 ≤ 300.
        XCTAssertLessThanOrEqual(grid(count: 9, width: 300).width, 300)
    }

    // MARK: Metric wiring

    func testGridMetricsDeriveCellFromThumbnailPlusPadding() {
        XCTAssertEqual(WindowGridMetrics.cellWidth,
                       WindowGridMetrics.thumbWidth + WindowGridMetrics.padding * 2, accuracy: accuracy)
        XCTAssertEqual(WindowGridMetrics.cellHeight,
                       WindowGridMetrics.thumbHeight + WindowGridMetrics.innerSpacing
                       + WindowGridMetrics.titleHeight + WindowGridMetrics.padding * 2, accuracy: accuracy)
    }
}

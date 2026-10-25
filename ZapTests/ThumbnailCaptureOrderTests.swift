import XCTest
@testable import Zap

/// Capture order for the window-preview batch (see
/// `SwitcherController.captureOrder`): the selected window fills in first, the
/// rest keep their list order.
final class ThumbnailCaptureOrderTests: XCTestCase {

    func testSelectedWindowIsCapturedFirst() {
        XCTAssertEqual(SwitcherController.captureOrder([1, 2, 3], selectedID: 2), [2, 1, 3])
    }

    func testOrderIsUnchangedWithoutASelection() {
        XCTAssertEqual(SwitcherController.captureOrder([1, 2, 3], selectedID: nil), [1, 2, 3])
    }

    func testUnknownSelectionLeavesOrderUnchanged() {
        XCTAssertEqual(SwitcherController.captureOrder([1, 2, 3], selectedID: 9), [1, 2, 3])
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertEqual(SwitcherController.captureOrder([], selectedID: 1), [])
    }
}

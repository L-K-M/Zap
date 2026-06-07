import XCTest
@testable import Zap

/// Tests the panel-height cap that keeps the switcher's top edge fixed: once the
/// window list is showing, the panel may only grow downward from its top to the
/// bottom of the screen, then the list scrolls. Coordinates are AppKit (y up), so
/// `screenBottom` is the visible frame's `minY` and `anchorTop` is the panel's top.
final class PanelHeightCapTests: XCTestCase {

    private let accuracy: CGFloat = 1e-6
    private let margin: CGFloat = 16

    private func cap(anchorTop: CGFloat?, screenBottom: CGFloat = 0, screenHeight: CGFloat = 1000) -> CGFloat {
        OverlayWindowController.maxPanelHeight(
            anchorTop: anchorTop, screenBottom: screenBottom,
            screenHeight: screenHeight, bottomMargin: margin, floor: 200)
    }

    // MARK: No anchor (initial placement, no window list yet)

    func testWithoutAnchorUsesFullScreenLessMargins() {
        XCTAssertEqual(cap(anchorTop: nil), 1000 - margin * 2, accuracy: accuracy)
    }

    // MARK: Anchored — grow downward only

    func testAnchoredUsesSpaceBelowTheTop() {
        // Top 700pt above the bottom ⇒ 700 - margin of usable downward space.
        XCTAssertEqual(cap(anchorTop: 700), 700 - margin, accuracy: accuracy)
    }

    func testAnchoredLeavesRoomSoTheTopNeverShiftsUp() {
        // The cap must be strictly less than the gap from the top to the screen
        // bottom, so the panel bottom stays above it and the frame isn't clamped up.
        let anchorTop: CGFloat = 640
        let gapToBottom = anchorTop - 0
        XCTAssertLessThan(cap(anchorTop: anchorTop), gapToBottom)
    }

    func testAnchoredHonorsNonZeroScreenBottom() {
        // visibleFrame above the Dock: screenBottom = 50, height = 900.
        XCTAssertEqual(cap(anchorTop: 600, screenBottom: 50, screenHeight: 900),
                       600 - 50 - margin, accuracy: accuracy)
    }

    // MARK: Bounds

    func testAnchorNearScreenTopIsBoundedByScreenHeight() {
        // A top near the very top would allow almost the whole height; the screen
        // cap (height - 2*margin) wins so the panel still fits with a bottom margin.
        XCTAssertEqual(cap(anchorTop: 990), 1000 - margin * 2, accuracy: accuracy)
    }

    func testTinySpaceBelowIsFlooredToMinimum() {
        // A very low anchor leaves little room; the floor keeps the panel usable.
        XCTAssertEqual(cap(anchorTop: 100), 200, accuracy: accuracy)
    }
}

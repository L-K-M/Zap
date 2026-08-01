import CoreGraphics
import XCTest
@testable import Zap

/// `IconRowMetrics` with a bleed, and the row geometry derived from it
/// (`UNJAILED.md §9`). Both `OverlayView` and `OverlayWindowController` read these,
/// so a disagreement here is a scroll position that doesn't match what's drawn.
final class IconRowBleedTests: XCTestCase {

    func testNoBleedKeepsTodaysGeometry() {
        XCTAssertEqual(IconRowMetrics.cellWidth(iconSize: 80), 96)
        XCTAssertEqual(IconRowMetrics.cellWidth(iconSize: 80, bleed: 0), 96)
        XCTAssertEqual(IconRowMetrics.imageExtent(iconSize: 80, bleed: 0), 80)
    }

    func testImageGrowsWithBleed() {
        XCTAssertEqual(IconRowMetrics.imageExtent(iconSize: 80, bleed: 0.08), 92.8, accuracy: 0.001)
        XCTAssertEqual(IconRowMetrics.imageExtent(iconSize: 100, bleed: 0.15), 130, accuracy: 0.001)
    }

    /// The default bleed is spent on padding the cell already had, so the row
    /// doesn't get wider — the point of deriving the cell from the bleed rather
    /// than just adding to it.
    func testDefaultBleedCostsNoExtraRowWidth() {
        XCTAssertEqual(IconRowMetrics.cellWidth(iconSize: 80, bleed: 0.08), 96)
        XCTAssertEqual(IconRowMetrics.cellWidth(iconSize: 120, bleed: 0.06), 136)
    }

    func testWideBleedEventuallyWidensTheCell() {
        // 80 * 1.3 = 104, past the 96 the padding covers.
        XCTAssertEqual(IconRowMetrics.cellWidth(iconSize: 80, bleed: 0.15), 104, accuracy: 0.001)
    }

    /// The image is always contained by its cell, which is what keeps bleeding art
    /// clear of `HorizontallyScrollable`'s `.clipped()` and the panel's `clipShape`.
    func testImageNeverExceedsItsCell() {
        for iconSize in stride(from: CGFloat(24), through: CGFloat(256), by: 8) {
            for bleed in [CGFloat(0), 0.03, 0.08, 0.15] {
                let image = IconRowMetrics.imageExtent(iconSize: iconSize, bleed: bleed)
                let cell = IconRowMetrics.cellWidth(iconSize: iconSize, bleed: bleed)
                XCTAssertLessThanOrEqual(image, cell,
                                         "image \(image) escaped cell \(cell) at size \(iconSize)")
            }
        }
    }

    func testBleedIsClamped() {
        XCTAssertEqual(IconRowMetrics.clampedBleed(-1), 0)
        XCTAssertEqual(IconRowMetrics.clampedBleed(2), IconRowMetrics.maximumBleed)
        XCTAssertEqual(IconRowMetrics.clampedBleed(.nan), 0)
        // Clamping applies through the derived values too.
        XCTAssertEqual(IconRowMetrics.imageExtent(iconSize: 80, bleed: 99),
                       IconRowMetrics.imageExtent(iconSize: 80, bleed: IconRowMetrics.maximumBleed))
    }

    // MARK: Geometry derived from a bled cell

    private func geometry(count: Int, iconSize: CGFloat, bleed: CGFloat, viewport: CGFloat) -> IconRowGeometry {
        IconRowGeometry(count: count,
                        cellWidth: IconRowMetrics.cellWidth(iconSize: iconSize, bleed: bleed),
                        spacing: IconRowMetrics.spacing,
                        viewport: viewport)
    }

    func testRowWidthAndScrollTrackTheBledCell() {
        let wide = geometry(count: 10, iconSize: 80, bleed: 0.15, viewport: 500)
        // 10 cells of 104 + 9 gaps of 12.
        XCTAssertEqual(wide.contentWidth, 10 * 104 + 9 * 12, accuracy: 0.001)
        XCTAssertEqual(wide.maxScroll, wide.contentWidth - 500, accuracy: 0.001)
        XCTAssertTrue(wide.overflows)
    }

    func testCenteringStaysCorrectWithBleed() {
        let row = geometry(count: 10, iconSize: 80, bleed: 0.15, viewport: 500)
        let pitch = 104.0 + 12.0
        let expected = 4 * pitch + 104 / 2 - 500 / 2
        XCTAssertEqual(row.centeredOffset(forIndex: 4), expected, accuracy: 0.001)
        // Still clamped to the ends.
        XCTAssertEqual(row.centeredOffset(forIndex: 0), 0)
        XCTAssertEqual(row.centeredOffset(forIndex: 9), row.maxScroll, accuracy: 0.001)
    }

    func testFadeStaysCorrectWithBleed() {
        let row = geometry(count: 10, iconSize: 80, bleed: 0.15, viewport: 500)
        XCTAssertEqual(row.fade(offset: 0, fadeWidth: 80).leading, 0)
        XCTAssertGreaterThan(row.fade(offset: 0, fadeWidth: 80).trailing, 0)
        XCTAssertEqual(row.fade(offset: row.maxScroll, fadeWidth: 80).trailing, 0)
        XCTAssertGreaterThan(row.fade(offset: row.maxScroll, fadeWidth: 80).leading, 0)
    }

    /// A row that fits without bleed can be pushed into scrolling by a wide one —
    /// the case where the two readers would drift if either ignored the bleed.
    func testBleedCanTipARowIntoScrolling() {
        let viewport: CGFloat = 540
        let snug = geometry(count: 5, iconSize: 80, bleed: 0, viewport: viewport)
        let bled = geometry(count: 5, iconSize: 80, bleed: 0.15, viewport: viewport)
        XCTAssertFalse(snug.overflows)
        XCTAssertTrue(bled.overflows)
    }
}

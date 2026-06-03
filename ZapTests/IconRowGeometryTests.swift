import XCTest
@testable import Zap

/// Tests for the scrolling icon row's geometry: how far it scrolls, where an icon
/// centres, and the edge fade as a function of the scroll offset.
///
/// Layout used by most cases: 96pt cells, 12pt spacing (so each step is 108pt).
final class IconRowGeometryTests: XCTestCase {

    private let accuracy: CGFloat = 1e-6

    private func geometry(count: Int, viewport: CGFloat) -> IconRowGeometry {
        IconRowGeometry(count: count, cellWidth: 96, spacing: 12, viewport: viewport)
    }

    // MARK: Content width / overflow

    func testContentWidthAndMaxScroll() {
        let g = geometry(count: 20, viewport: 1000)
        XCTAssertEqual(g.contentWidth, 2148, accuracy: accuracy)  // 20*96 + 19*12
        XCTAssertEqual(g.maxScroll, 1148, accuracy: accuracy)
        XCTAssertTrue(g.overflows)
    }

    func testRowThatFitsDoesNotOverflowOrFade() {
        let g = geometry(count: 3, viewport: 1000)               // 312pt of content
        XCTAssertEqual(g.maxScroll, 0, accuracy: accuracy)
        XCTAssertFalse(g.overflows)
        XCTAssertEqual(g.fade(offset: 0, fadeWidth: 80), .none)
        XCTAssertEqual(g.centeredOffset(forIndex: 2), 0, accuracy: accuracy)
    }

    func testClampBoundsToScrollableRange() {
        let g = geometry(count: 20, viewport: 1000)
        XCTAssertEqual(g.clamp(-50), 0, accuracy: accuracy)
        XCTAssertEqual(g.clamp(99_999), g.maxScroll, accuracy: accuracy)
        XCTAssertEqual(g.clamp(500), 500, accuracy: accuracy)
    }

    // MARK: Which edge fades

    func testScrolledToStartFadesOnlyTheRight() {
        let fade = geometry(count: 20, viewport: 1000).fade(offset: 0, fadeWidth: 80)
        XCTAssertEqual(fade.leading, 0, accuracy: accuracy)
        XCTAssertEqual(fade.trailing, 1, accuracy: accuracy)
    }

    func testScrolledToEndFadesOnlyTheLeft() {
        let g = geometry(count: 20, viewport: 1000)
        let fade = g.fade(offset: g.maxScroll, fadeWidth: 80)
        XCTAssertEqual(fade.leading, 1, accuracy: accuracy)
        XCTAssertEqual(fade.trailing, 0, accuracy: accuracy)
    }

    func testMidScrollFadesBothEdges() {
        let g = geometry(count: 20, viewport: 1000)
        let fade = g.fade(offset: g.maxScroll / 2, fadeWidth: 80)
        XCTAssertGreaterThan(fade.leading, 0)
        XCTAssertGreaterThan(fade.trailing, 0)
    }

    // MARK: Centred offset drives the fade ends

    func testCenteringFirstAndLastClampsToTheEnds() {
        let g = geometry(count: 20, viewport: 1000)
        XCTAssertEqual(g.centeredOffset(forIndex: 0), 0, accuracy: accuracy)
        XCTAssertEqual(g.centeredOffset(forIndex: 19), g.maxScroll, accuracy: accuracy)
        // Centring the first icon leaves the left crisp; the last, the right.
        XCTAssertEqual(g.fade(offset: g.centeredOffset(forIndex: 0), fadeWidth: 80).leading, 0, accuracy: accuracy)
        XCTAssertEqual(g.fade(offset: g.centeredOffset(forIndex: 19), fadeWidth: 80).trailing, 0, accuracy: accuracy)
    }

    func testCenteredOffsetClampsOutOfRangeIndex() {
        let g = geometry(count: 5, viewport: 480)
        XCTAssertEqual(g.centeredOffset(forIndex: 99), g.centeredOffset(forIndex: 4), accuracy: accuracy)
        XCTAssertEqual(g.centeredOffset(forIndex: -3), g.centeredOffset(forIndex: 0), accuracy: accuracy)
    }

    // MARK: Exact ramp values

    /// 5 icons (528pt) in a 480pt viewport ⇒ 48pt of scroll, 80pt ramp.
    func testPartialFadeRampValues() {
        let g = geometry(count: 5, viewport: 480)
        XCTAssertEqual(g.maxScroll, 48, accuracy: accuracy)

        // Start: no left fade, 48/80 of a right fade.
        XCTAssertEqual(g.fade(offset: 0, fadeWidth: 80).leading, 0, accuracy: accuracy)
        XCTAssertEqual(g.fade(offset: 0, fadeWidth: 80).trailing, 0.6, accuracy: accuracy)
        // Middle of the range: symmetric half-ramp.
        XCTAssertEqual(g.fade(offset: 24, fadeWidth: 80).leading, 0.3, accuracy: accuracy)
        XCTAssertEqual(g.fade(offset: 24, fadeWidth: 80).trailing, 0.3, accuracy: accuracy)
        // End: 48/80 of a left fade, no right fade.
        XCTAssertEqual(g.fade(offset: 48, fadeWidth: 80).leading, 0.6, accuracy: accuracy)
        XCTAssertEqual(g.fade(offset: 48, fadeWidth: 80).trailing, 0, accuracy: accuracy)
    }

    // MARK: Ramp width

    func testRampInsetIsFadeWidthOverViewport() {
        let fade = geometry(count: 20, viewport: 480).fade(offset: 0, fadeWidth: 80)
        XCTAssertEqual(fade.inset, 80.0 / 480.0, accuracy: accuracy)
    }

    func testRampIsClampedToAThirdOfTheViewport() {
        let g = geometry(count: 5, viewport: 480)
        let fade = g.fade(offset: 0, fadeWidth: 10_000)
        XCTAssertEqual(fade.inset, 1.0 / 3.0, accuracy: accuracy)   // ramp clamped to 160
        XCTAssertEqual(fade.trailing, 48.0 / 160.0, accuracy: accuracy)
    }
}

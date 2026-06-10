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
        // 1148pt hidden on the right, far more than the 80pt ramp, so the trailing
        // band is the full ramp wide; the flush left edge stays crisp.
        let fade = geometry(count: 20, viewport: 1000).fade(offset: 0, fadeWidth: 80)
        XCTAssertEqual(fade.leading, 0, accuracy: accuracy)
        XCTAssertEqual(fade.trailing, 80.0 / 1000.0, accuracy: accuracy)
    }

    func testScrolledToEndFadesOnlyTheLeft() {
        let g = geometry(count: 20, viewport: 1000)
        let fade = g.fade(offset: g.maxScroll, fadeWidth: 80)
        XCTAssertEqual(fade.leading, 80.0 / 1000.0, accuracy: accuracy)
        XCTAssertEqual(fade.trailing, 0, accuracy: accuracy)
    }

    func testMidScrollFadesBothEdges() {
        let g = geometry(count: 20, viewport: 1000)
        let fade = g.fade(offset: g.maxScroll / 2, fadeWidth: 80)
        // Plenty hidden on both sides, so each band is the full ramp wide.
        XCTAssertEqual(fade.leading, 80.0 / 1000.0, accuracy: accuracy)
        XCTAssertEqual(fade.trailing, 80.0 / 1000.0, accuracy: accuracy)
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

    /// 5 icons (528pt) in a 480pt viewport ⇒ only 48pt of overflow, less than the
    /// 80pt ramp, so each fade band is exactly the content hidden on that side.
    func testPartialFadeRampValues() {
        let g = geometry(count: 5, viewport: 480)
        XCTAssertEqual(g.maxScroll, 48, accuracy: accuracy)

        // Start: left crisp, the 48pt hidden on the right as a 48/480 band.
        XCTAssertEqual(g.fade(offset: 0, fadeWidth: 80).leading, 0, accuracy: accuracy)
        XCTAssertEqual(g.fade(offset: 0, fadeWidth: 80).trailing, 48.0 / 480.0, accuracy: accuracy)
        // Middle of the range: the hidden content splits evenly between the edges.
        XCTAssertEqual(g.fade(offset: 24, fadeWidth: 80).leading, 24.0 / 480.0, accuracy: accuracy)
        XCTAssertEqual(g.fade(offset: 24, fadeWidth: 80).trailing, 24.0 / 480.0, accuracy: accuracy)
        // End: 48pt hidden on the left, right crisp.
        XCTAssertEqual(g.fade(offset: 48, fadeWidth: 80).leading, 48.0 / 480.0, accuracy: accuracy)
        XCTAssertEqual(g.fade(offset: 48, fadeWidth: 80).trailing, 0, accuracy: accuracy)
    }

    // MARK: Band width

    func testFadeBandIsFadeWidthOverViewportWhenContentExceedsIt() {
        // Far more overflow than the ramp, so the trailing band is the full ramp wide.
        let fade = geometry(count: 20, viewport: 480).fade(offset: 0, fadeWidth: 80)
        XCTAssertEqual(fade.trailing, 80.0 / 480.0, accuracy: accuracy)
    }

    func testRampIsClampedToAThirdOfTheViewport() {
        // A huge fadeWidth is clamped to viewport/3 (160); with ample overflow the
        // band reaches that clamp, so it spans 160/480 = 1/3 of the viewport.
        let fade = geometry(count: 20, viewport: 480).fade(offset: 0, fadeWidth: 10_000)
        XCTAssertEqual(fade.trailing, 1.0 / 3.0, accuracy: accuracy)
    }

    // MARK: Regression — soft fade survives to the end of the scroll

    /// Near the end of a long row a small sliver is still hidden on the right, so the
    /// trailing edge must keep a (narrow) soft fade tracking that sliver rather than
    /// hardening into an opaque cut as it nears flush.
    func testNearEndKeepsSoftFadeOverHiddenSliver() {
        let g = geometry(count: 20, viewport: 1000)        // 1148pt of overflow
        let hidden: CGFloat = 20
        let fade = g.fade(offset: g.maxScroll - hidden, fadeWidth: 80)
        XCTAssertGreaterThan(fade.trailing, 0)
        XCTAssertEqual(fade.trailing, hidden / 1000.0, accuracy: accuracy)
    }
}

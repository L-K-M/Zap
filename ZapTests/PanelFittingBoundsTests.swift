import XCTest
@testable import Zap

/// Tests the "size the panel to fit the smallest display when mirroring" rule that
/// keeps the all-screens panel from spilling off smaller monitors.
final class PanelFittingBoundsTests: XCTestCase {

    private let big = CGSize(width: 3840, height: 2160)
    private let small = CGSize(width: 1280, height: 800)

    func testUsesCurrentScreenWhenNotMirroring() {
        let bounds = OverlayWindowController.panelFittingBounds(
            allScreens: false, screens: [big, small], current: big)
        XCTAssertEqual(bounds, big)
    }

    func testShrinksToSmallestScreenWhenMirroring() {
        // Main is the big display; a mirrored small display must constrain the size.
        let bounds = OverlayWindowController.panelFittingBounds(
            allScreens: true, screens: [big, small], current: big)
        XCTAssertEqual(bounds, small)
    }

    func testTakesSmallestWidthAndHeightIndependently() {
        // Mixed: one screen is the narrowest, another the shortest.
        let wide = CGSize(width: 3440, height: 1440)
        let tall = CGSize(width: 1080, height: 1920)
        let bounds = OverlayWindowController.panelFittingBounds(
            allScreens: true, screens: [wide, tall], current: wide)
        XCTAssertEqual(bounds, CGSize(width: 1080, height: 1440))
    }

    func testFallsBackToCurrentWhenNoScreensReported() {
        let bounds = OverlayWindowController.panelFittingBounds(
            allScreens: true, screens: [], current: small)
        XCTAssertEqual(bounds, small)
    }

    func testSingleScreenIsUnchangedByMirroring() {
        let bounds = OverlayWindowController.panelFittingBounds(
            allScreens: true, screens: [big], current: big)
        XCTAssertEqual(bounds, big)
    }
}

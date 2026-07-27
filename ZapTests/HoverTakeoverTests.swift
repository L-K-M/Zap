import XCTest
@testable import Zap

/// The rule that stops a panel appearing under a resting cursor from hijacking
/// the selection (see `OverlayWindowController.hoverShouldTakeOver`).
final class HoverTakeoverTests: XCTestCase {

    func testUnarmedGateAlwaysAcceptsHover() {
        // No origin recorded (the gate has already opened, or the panel isn't
        // freshly presented): hovers pass straight through.
        XCTAssertTrue(OverlayWindowController.hoverShouldTakeOver(
            origin: nil, current: NSPoint(x: 100, y: 100)))
    }

    func testStationaryPointerDoesNotTakeOver() {
        let origin = NSPoint(x: 640, y: 480)
        XCTAssertFalse(OverlayWindowController.hoverShouldTakeOver(
            origin: origin, current: origin))
    }

    func testSubThresholdJitterDoesNotTakeOver() {
        // A pixel or two of tremor/rounding must not count as "the user moved".
        let origin = NSPoint(x: 640, y: 480)
        XCTAssertFalse(OverlayWindowController.hoverShouldTakeOver(
            origin: origin, current: NSPoint(x: 642, y: 481)))
    }

    func testMovementOnEitherAxisTakesOver() {
        let origin = NSPoint(x: 640, y: 480)
        XCTAssertTrue(OverlayWindowController.hoverShouldTakeOver(
            origin: origin, current: NSPoint(x: 660, y: 480)))
        XCTAssertTrue(OverlayWindowController.hoverShouldTakeOver(
            origin: origin, current: NSPoint(x: 640, y: 500)))
    }

    func testMovementInEitherDirectionTakesOver() {
        let origin = NSPoint(x: 640, y: 480)
        XCTAssertTrue(OverlayWindowController.hoverShouldTakeOver(
            origin: origin, current: NSPoint(x: 600, y: 440)))
    }

    func testThresholdIsExclusive() {
        // Exactly at the threshold is still "not moved"; just past it counts.
        let origin = NSPoint(x: 0, y: 0)
        XCTAssertFalse(OverlayWindowController.hoverShouldTakeOver(
            origin: origin, current: NSPoint(x: 3, y: 0), threshold: 3))
        XCTAssertTrue(OverlayWindowController.hoverShouldTakeOver(
            origin: origin, current: NSPoint(x: 3.5, y: 0), threshold: 3))
    }
}

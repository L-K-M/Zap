import XCTest
@testable import Zap

/// Tests `AngleDial.adjustedAngle`, the shared 5°-step path used by both the
/// keyboard move command and VoiceOver's increment/decrement actions.
final class AngleDialAdjustmentTests: XCTestCase {

    func testIncrementStepsForward() {
        XCTAssertEqual(AngleDial.adjustedAngle(0, by: 5), 5)
    }

    func testDecrementFromZeroWrapsTo355() {
        XCTAssertEqual(AngleDial.adjustedAngle(0, by: -5), 355)
    }

    func testIncrementPast360WrapsAround() {
        XCTAssertEqual(AngleDial.adjustedAngle(358, by: 5), 3)
        XCTAssertEqual(AngleDial.adjustedAngle(355, by: 5), 0)
        XCTAssertEqual(AngleDial.adjustedAngle(0, by: 725), 5)
    }

    func testDecrementBelowZeroWrapsAround() {
        XCTAssertEqual(AngleDial.adjustedAngle(2, by: -5), 357)
        XCTAssertEqual(AngleDial.adjustedAngle(0, by: -725), 355)
    }

    func testAngleAt360NormalizesToZero() {
        XCTAssertEqual(AngleDial.adjustedAngle(360, by: 0), 0)
        XCTAssertEqual(AngleDial.adjustedAngle(0, by: 360), 0)
        XCTAssertEqual(AngleDial.adjustedAngle(0, by: -360), 0)
    }

    func testNegativeAngleNormalizesIntoRange() {
        XCTAssertEqual(AngleDial.adjustedAngle(-5, by: 0), 355)
    }

    func testNonFiniteInputsFallBackToZero() {
        XCTAssertEqual(AngleDial.adjustedAngle(.nan, by: 5), 0)
        XCTAssertEqual(AngleDial.adjustedAngle(10, by: .nan), 0)
        XCTAssertEqual(AngleDial.adjustedAngle(.infinity, by: -5), 0)
        XCTAssertEqual(AngleDial.adjustedAngle(10, by: .infinity), 0)
    }

    /// Finite inputs can still overflow to infinity when summed; that must fall
    /// back to 0 just like a non-finite input would.
    func testFiniteSumOverflowFallsBackToZero() {
        XCTAssertEqual(AngleDial.adjustedAngle(.greatestFiniteMagnitude,
                                               by: .greatestFiniteMagnitude), 0)
    }

    /// The announced value is normalized after rounding, so 359.7 (which rounds
    /// to 360) announces 0 rather than an out-of-range reading.
    func testAnnouncedDegreesNormalizeRoundedBoundary() {
        XCTAssertEqual(AngleDial.announcedDegrees(359.7), 0)
        XCTAssertEqual(AngleDial.announcedDegrees(358.6), 359)
        XCTAssertEqual(AngleDial.announcedDegrees(-1), 359)
        XCTAssertEqual(AngleDial.announcedDegrees(360), 0)
    }

    /// Invalid bindings announce 0; huge-but-finite bindings announce some
    /// in-range remainder rather than overflowing the Int conversion.
    func testAnnouncedDegreesHandleInvalidAndHugeBindings() {
        XCTAssertEqual(AngleDial.announcedDegrees(.nan), 0)
        XCTAssertEqual(AngleDial.announcedDegrees(.infinity), 0)
        XCTAssertEqual(AngleDial.announcedDegrees(-.infinity), 0)
        for angle in [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude] {
            XCTAssertTrue((0..<360).contains(AngleDial.announcedDegrees(angle)))
        }
    }
}

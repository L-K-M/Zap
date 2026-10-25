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
    }

    func testDecrementBelowZeroWrapsAround() {
        XCTAssertEqual(AngleDial.adjustedAngle(2, by: -5), 357)
    }

    func testAngleAt360NormalizesToZero() {
        XCTAssertEqual(AngleDial.adjustedAngle(360, by: 0), 0)
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
}

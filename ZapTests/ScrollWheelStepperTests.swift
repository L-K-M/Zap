import XCTest
@testable import Zap

final class ScrollWheelStepperTests: XCTestCase {

    func testNoMovementProducesNoStep() {
        var acc: CGFloat = 0
        XCTAssertEqual(ScrollWheelStepper.steps(raw: 0, pointsPerIcon: 1, accumulator: &acc), 0)
        XCTAssertEqual(acc, 0)
    }

    func testZeroPointsPerIconIsIgnored() {
        var acc: CGFloat = 0
        XCTAssertEqual(ScrollWheelStepper.steps(raw: 50, pointsPerIcon: 0, accumulator: &acc), 0)
    }

    func testMouseWheelNotchAdvancesOneIcon() {
        var acc: CGFloat = 0
        // A line-based notch: negative advances toward later icons (+1).
        XCTAssertEqual(ScrollWheelStepper.steps(raw: -1, pointsPerIcon: 1, accumulator: &acc), 1)
        XCTAssertEqual(acc, 0, accuracy: 1e-9)
        // The opposite direction steps back toward earlier icons (-1).
        XCTAssertEqual(ScrollWheelStepper.steps(raw: 1, pointsPerIcon: 1, accumulator: &acc), -1)
    }

    func testTrackpadDeltasAccumulateUntilAWholeIcon() {
        var acc: CGFloat = 0
        // Half an icon at a time: first event doesn't step yet.
        XCTAssertEqual(ScrollWheelStepper.steps(raw: -30, pointsPerIcon: 60, accumulator: &acc), 0)
        XCTAssertEqual(acc, -0.5, accuracy: 1e-9)
        // Second half crosses the threshold → one step, remainder cleared.
        XCTAssertEqual(ScrollWheelStepper.steps(raw: -30, pointsPerIcon: 60, accumulator: &acc), 1)
        XCTAssertEqual(acc, 0, accuracy: 1e-9)
    }

    func testFastScrollStepsMultipleIconsAtOnce() {
        var acc: CGFloat = 0
        XCTAssertEqual(ScrollWheelStepper.steps(raw: -180, pointsPerIcon: 60, accumulator: &acc), 3)
        XCTAssertEqual(acc, 0, accuracy: 1e-9)
    }

    func testRemainderCarriesAcrossCalls() {
        var acc: CGFloat = 0
        // 1.5 icons → 1 step now, 0.5 carried.
        XCTAssertEqual(ScrollWheelStepper.steps(raw: -90, pointsPerIcon: 60, accumulator: &acc), 1)
        XCTAssertEqual(acc, -0.5, accuracy: 1e-9)
        // Another 1.5 → 2.0 total → 2 steps, nothing carried.
        XCTAssertEqual(ScrollWheelStepper.steps(raw: -90, pointsPerIcon: 60, accumulator: &acc), 2)
        XCTAssertEqual(acc, 0, accuracy: 1e-9)
    }
}

import XCTest
@testable import Zap

/// The always-on polls must be coalescible (a tolerance) and must keep firing
/// while a menu tracks events (common run-loop modes).
final class BackgroundPollTests: XCTestCase {

    func testPollsRepeatWithATolerance() {
        let timer = BackgroundPoll.schedule(every: 2) {}
        defer { timer.invalidate() }

        XCTAssertTrue(timer.isValid)
        XCTAssertEqual(timer.timeInterval, 2)
        XCTAssertEqual(timer.tolerance, BackgroundPoll.tolerance)
        XCTAssertGreaterThan(timer.tolerance, 0)
    }

    func testShortPollsGetAProportionateTolerance() {
        let timer = BackgroundPoll.schedule(every: 0.2) {}
        defer { timer.invalidate() }

        XCTAssertEqual(timer.tolerance, 0.05, accuracy: 0.0001)
    }

    func testPollsKeepFiringWhileAMenuIsTracking() {
        var fired = 0
        let timer = BackgroundPoll.schedule(every: 0.01) { fired += 1 }
        defer { timer.invalidate() }

        // `.eventTracking` is the mode an open menu runs the main loop in.
        let deadline = Date(timeIntervalSinceNow: 2)
        while fired < 2 && Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertGreaterThanOrEqual(fired, 2)
    }
}

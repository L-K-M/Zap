import XCTest
@testable import Zap

/// The always-on polls must be coalescible (a tolerance) and must keep firing
/// while a menu tracks events (common run-loop modes).
final class BackgroundPollTests: XCTestCase {

    func testPollsRepeatWithATolerance() {
        let timer = BackgroundPoll.schedule(every: 2) { _ in }
        defer { timer.invalidate() }

        XCTAssertTrue(timer.isValid)
        XCTAssertEqual(timer.timeInterval, 2)
        XCTAssertEqual(timer.tolerance, BackgroundPoll.tolerance)
        XCTAssertGreaterThan(timer.tolerance, 0)
    }

    func testPollsFireWhileAMenuIsTracking() {
        var fired = 0
        let timer = BackgroundPoll.schedule(every: 0.01) { _ in fired += 1 }
        defer { timer.invalidate() }

        // `.eventTracking` is the mode an open menu runs the main loop in.
        let deadline = Date(timeIntervalSinceNow: 2)
        while fired == 0 && Date() < deadline {
            RunLoop.main.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertGreaterThan(fired, 0)
    }
}

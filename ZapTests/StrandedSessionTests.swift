import XCTest
@testable import Zap

/// The recovery rule for a session whose ⌘ key-up was dropped while the system
/// had the event tap disabled (see
/// `SwitcherController.shouldEndStrandedSession(isSessionActive:usesEventTap:commandDown:)`).
final class StrandedSessionTests: XCTestCase {

    func testCommandReleasedDuringAnEventTapSessionIsStranded() {
        // The commit event never arrived, but the key is demonstrably up.
        XCTAssertTrue(SwitcherController.shouldEndStrandedSession(
            isSessionActive: true, usesEventTap: true, commandDown: false))
    }

    func testHeldCommandIsANormalLiveSession() {
        XCTAssertFalse(SwitcherController.shouldEndStrandedSession(
            isSessionActive: true, usesEventTap: true, commandDown: true))
    }

    func testNoSessionIsNeverStranded() {
        XCTAssertFalse(SwitcherController.shouldEndStrandedSession(
            isSessionActive: false, usesEventTap: true, commandDown: false))
    }

    func testFallbackModeIsNeverStranded() {
        // ⌥-Tab sessions have no ⌘ to watch and end on their own auto-commit
        // timer; polling the Command key there would cancel them instantly.
        XCTAssertFalse(SwitcherController.shouldEndStrandedSession(
            isSessionActive: true, usesEventTap: false, commandDown: false))
        XCTAssertFalse(SwitcherController.shouldEndStrandedSession(
            isSessionActive: true, usesEventTap: false, commandDown: true))
    }
}

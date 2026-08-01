import XCTest
@testable import Zap

/// The retry rule guarding `WindowEnumerator.activate`'s verification pass:
/// re-request activation only while nothing has changed since the request, so a
/// rescue retry can never undo a newer, deliberate activation (e.g. the user's
/// own ⌘-Tab switch landing right after Settings closed).
final class ActivationRetryTests: XCTestCase {

    func testRetriesWhileFrontmostIsUnchangedAndTargetNotFrontmost() {
        // The request was ignored: the app we tried to leave is still in front.
        XCTAssertTrue(
            WindowEnumerator.shouldRetryActivation(frontmostPID: 100, targetPID: 200, originPID: 100)
        )
    }

    func testStopsOnceTargetIsFrontmost() {
        XCTAssertFalse(
            WindowEnumerator.shouldRetryActivation(frontmostPID: 200, targetPID: 200, originPID: 100)
        )
    }

    func testStopsWhenADifferentAppBecameFrontmost() {
        // The user switched elsewhere in the meantime — re-requesting would
        // yank them back out of that deliberate switch.
        XCTAssertFalse(
            WindowEnumerator.shouldRetryActivation(frontmostPID: 300, targetPID: 200, originPID: 100)
        )
    }

    func testRetriesWhileNothingIsFrontmostYet() {
        // No frontmost reading at request time and none now: still unresolved.
        XCTAssertTrue(
            WindowEnumerator.shouldRetryActivation(frontmostPID: nil, targetPID: 200, originPID: nil)
        )
    }
}

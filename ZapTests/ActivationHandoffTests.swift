import XCTest
@testable import Zap

final class ActivationHandoffTests: XCTestCase {

    func testRestoresWhileZapIsStillFrontmost() {
        XCTAssertTrue(
            ActivationHandoff.shouldRestore(targetPID: 200, targetIsTerminated: false,
                                             zapIsActive: true, ownPID: 100)
        )
    }

    func testDoesNotRestoreAfterUserActivatesAnotherApp() {
        XCTAssertFalse(
            ActivationHandoff.shouldRestore(targetPID: 200, targetIsTerminated: false,
                                             zapIsActive: false, ownPID: 100)
        )
    }

    func testDoesNotRestoreTerminatedApp() {
        XCTAssertFalse(
            ActivationHandoff.shouldRestore(targetPID: 200, targetIsTerminated: true,
                                             zapIsActive: true, ownPID: 100)
        )
    }

    func testDoesNotRestoreZapItself() {
        XCTAssertFalse(
            ActivationHandoff.shouldRestore(targetPID: 100, targetIsTerminated: false,
                                             zapIsActive: true, ownPID: 100)
        )
    }

    // MARK: Nesting

    /// The predicate above is pure and easy; the nesting is where this type can
    /// break quietly. Settings can put an update alert on top of itself, and only
    /// the *last* presentation to close may hand activation back — an inner one
    /// doing it would drop the user out of the Settings window still on screen.
    ///
    /// Nothing is activated during these tests: `finish` returns before touching
    /// `NSApp` unless Zap is the active application, which a test bundle is not.
    /// What is asserted is the counting that gates it.
    func testOnlyTheLastPresentationToCloseEndsTheHandoff() {
        XCTAssertEqual(ActivationHandoff.openPresentations, 0, "a previous test leaked one")

        let settings = ActivationHandoff()
        XCTAssertEqual(ActivationHandoff.openPresentations, 1)

        let alertOverSettings = ActivationHandoff()
        XCTAssertEqual(ActivationHandoff.openPresentations, 2)

        alertOverSettings.restore()
        XCTAssertEqual(ActivationHandoff.openPresentations, 1,
                       "the inner presentation must not end the handoff")

        settings.restore()
        XCTAssertEqual(ActivationHandoff.openPresentations, 0)
    }

    /// `restore()` then release must not decrement twice — `deinit` ends a
    /// presentation that was never restored, and the two paths share one counter.
    func testRestoringThenReleasingCountsOnce() {
        XCTAssertEqual(ActivationHandoff.openPresentations, 0, "a previous test leaked one")

        let outer = ActivationHandoff()
        do {
            let inner = ActivationHandoff()
            inner.restore()
            XCTAssertEqual(ActivationHandoff.openPresentations, 1)
        }  // `inner` released here, already finished
        XCTAssertEqual(ActivationHandoff.openPresentations, 1,
                       "deinit must not decrement a presentation restore() already ended")

        outer.restore()
        XCTAssertEqual(ActivationHandoff.openPresentations, 0)
    }

    /// A presentation dropped without `restore()` still has to release its slot,
    /// or every later handoff would think something of Zap's was still open.
    func testReleasingWithoutRestoringStillEndsThePresentation() {
        XCTAssertEqual(ActivationHandoff.openPresentations, 0, "a previous test leaked one")

        do { _ = ActivationHandoff() }
        XCTAssertEqual(ActivationHandoff.openPresentations, 0)
    }
}

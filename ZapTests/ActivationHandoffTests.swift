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
}

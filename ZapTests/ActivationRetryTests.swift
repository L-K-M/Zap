import XCTest
@testable import Zap

final class ActivationRetryTests: XCTestCase {

    func testRetriesWhileRequestIsCurrentAndFrontmostIsUnchanged() {
        XCTAssertTrue(
            WindowEnumerator.shouldRetryActivation(frontmostPID: 100, targetPID: 200,
                                                    originPID: 100, requestGeneration: 4,
                                                    currentGeneration: 4)
        )
    }

    func testStopsOnceTargetIsFrontmost() {
        XCTAssertFalse(
            WindowEnumerator.shouldRetryActivation(frontmostPID: 200, targetPID: 200,
                                                    originPID: 100, requestGeneration: 4,
                                                    currentGeneration: 4)
        )
    }

    func testStopsWhenDifferentAppBecameFrontmost() {
        XCTAssertFalse(
            WindowEnumerator.shouldRetryActivation(frontmostPID: 300, targetPID: 200,
                                                    originPID: 100, requestGeneration: 4,
                                                    currentGeneration: 4)
        )
    }

    func testStopsWhenActivationGenerationAdvances() {
        XCTAssertFalse(
            WindowEnumerator.shouldRetryActivation(frontmostPID: 100, targetPID: 200,
                                                    originPID: 100, requestGeneration: 4,
                                                    currentGeneration: 5)
        )
    }

    func testRetriesWhileNothingIsFrontmostYet() {
        XCTAssertTrue(
            WindowEnumerator.shouldRetryActivation(frontmostPID: nil, targetPID: 200,
                                                    originPID: nil, requestGeneration: 4,
                                                    currentGeneration: 4)
        )
    }
}

import XCTest
@testable import Zap

/// The test guard must be trustworthy in exactly one direction: it must read
/// true while these tests run, or the app's global hooks install under XCTest.
final class TestEnvironmentTests: XCTestCase {

    func testIsRunningTestsUnderXCTest() {
        XCTAssertTrue(TestEnvironment.isRunningTests)
    }
}

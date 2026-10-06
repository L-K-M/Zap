import CoreGraphics
import XCTest
@testable import Zap

final class WindowServerVisibilityTests: XCTestCase {
    func testMissingOnscreenFlagMeansOffscreen() {
        XCTAssertEqual(WindowServerVisibility.isOnscreen(in: [
            [kCGWindowNumber as String: 42]
        ], windowNumber: 42), false)
    }

    func testOnlyMatchingWindowDeterminesVisibility() {
        XCTAssertEqual(WindowServerVisibility.isOnscreen(in: [
            [kCGWindowNumber as String: 43, kCGWindowIsOnscreen as String: true],
            [kCGWindowNumber as String: 42, kCGWindowIsOnscreen as String: false]
        ], windowNumber: 42), false)
    }

    func testVisibleWindowIsHealthy() {
        XCTAssertEqual(WindowServerVisibility.isOnscreen(in: [
            [kCGWindowNumber as String: 42, kCGWindowIsOnscreen as String: true]
        ], windowNumber: 42), true)
    }

    func testAbsentWindowIsOffscreenButUnavailableQueryIsUnknown() {
        XCTAssertEqual(WindowServerVisibility.isOnscreen(in: [], windowNumber: 42), false)
        XCTAssertNil(WindowServerVisibility.isOnscreen(in: nil, windowNumber: 42))
    }
}

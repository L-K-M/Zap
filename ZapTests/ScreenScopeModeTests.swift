import XCTest
@testable import Zap

/// The two behavioral flags that drive the scoped-list filter.
final class ScreenScopeModeTests: XCTestCase {

    func testOffIsNeitherScopedNorExclusionOverriding() {
        XCTAssertFalse(ScreenScopeMode.off.isScoped)
        XCTAssertTrue(ScreenScopeMode.off.appliesExclusions)
    }

    func testRespectingExclusionsIsScopedAndKeepsExclusions() {
        XCTAssertTrue(ScreenScopeMode.scopedRespectingExclusions.isScoped)
        XCTAssertTrue(ScreenScopeMode.scopedRespectingExclusions.appliesExclusions)
    }

    func testIgnoringExclusionsIsScopedAndDropsExclusions() {
        XCTAssertTrue(ScreenScopeMode.scopedIgnoringExclusions.isScoped)
        XCTAssertFalse(ScreenScopeMode.scopedIgnoringExclusions.appliesExclusions)
    }

    func testRawValuesAreStableForPersistence() {
        // These strings are stored in UserDefaults; changing them silently drops
        // users' saved per-display settings.
        XCTAssertEqual(ScreenScopeMode.off.rawValue, "off")
        XCTAssertEqual(ScreenScopeMode.scopedRespectingExclusions.rawValue, "scopedRespectingExclusions")
        XCTAssertEqual(ScreenScopeMode.scopedIgnoringExclusions.rawValue, "scopedIgnoringExclusions")
    }
}

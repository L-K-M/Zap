import XCTest
@testable import Zap

/// Tests the rule that gates per-display scoping behind "2+ displays, mirroring off",
/// so a stored mode never strands the user when they drop to a single display.
final class EffectiveScopeModeTests: XCTestCase {

    func testStoredModeAppliesWithMultipleDisplaysAndNoMirroring() {
        for stored in ScreenScopeMode.allCases {
            XCTAssertEqual(
                SwitcherController.effectiveScopeMode(stored: stored, mirroring: false, displayCount: 2),
                stored)
        }
    }

    func testSingleDisplaySuppressesScoping() {
        XCTAssertEqual(
            SwitcherController.effectiveScopeMode(stored: .scopedIgnoringExclusions,
                                                  mirroring: false, displayCount: 1),
            .off)
    }

    func testZeroDisplaysSuppressesScoping() {
        XCTAssertEqual(
            SwitcherController.effectiveScopeMode(stored: .scopedRespectingExclusions,
                                                  mirroring: false, displayCount: 0),
            .off)
    }

    func testMirroringSuppressesScopingEvenWithMultipleDisplays() {
        XCTAssertEqual(
            SwitcherController.effectiveScopeMode(stored: .scopedRespectingExclusions,
                                                  mirroring: true, displayCount: 3),
            .off)
    }

    func testOffStaysOffWhenActive() {
        XCTAssertEqual(
            SwitcherController.effectiveScopeMode(stored: .off, mirroring: false, displayCount: 2),
            .off)
    }
}

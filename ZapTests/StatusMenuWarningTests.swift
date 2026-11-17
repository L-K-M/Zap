import XCTest
@testable import Zap

/// When the status menu explains that ⌘-Tab isn't being intercepted
/// (`SwitcherInputMode.statusMenuWarning(alternateForced:)`).
final class StatusMenuWarningTests: XCTestCase {

    func testHealthyTapShowsNothing() {
        XCTAssertNil(SwitcherInputMode.eventTap.statusMenuWarning(alternateForced: false))
        XCTAssertNil(SwitcherInputMode.eventTap.statusMenuWarning(alternateForced: true))
    }

    func testPauseIsAlreadyExplainedByTheMenu() {
        XCTAssertNil(SwitcherInputMode.paused.statusMenuWarning(alternateForced: false))
    }

    /// The case this exists for: Accessibility is missing, so Zap is on ⌥-Tab
    /// without the user having asked for it.
    func testUnchosenFallbackPointsAtAccessibility() throws {
        let warning = try XCTUnwrap(SwitcherInputMode.fallback.statusMenuWarning(alternateForced: false))
        XCTAssertTrue(warning.contains("⌥-Tab"))
        XCTAssertTrue(warning.contains("Accessibility"))
    }

    func testChosenFallbackIsNotAWarning() {
        XCTAssertNil(SwitcherInputMode.fallback.statusMenuWarning(alternateForced: true))
    }

    func testNoTriggerAtAllIsAlwaysAWarning() {
        XCTAssertNotNil(SwitcherInputMode.unavailable.statusMenuWarning(alternateForced: false))
        XCTAssertNotNil(SwitcherInputMode.unavailable.statusMenuWarning(alternateForced: true))
    }
}

import XCTest
@testable import Zap

/// The status menu's explanation and Accessibility action
/// (`SwitcherInputMode.statusMenuWarning(alternateForced:accessibilityTrusted:)`
/// and `showsAccessibilityAction(alternateForced:accessibilityTrusted:)`).
final class StatusMenuWarningTests: XCTestCase {

    func testHealthyTapShowsNothing() {
        for trusted in [false, true] {
            XCTAssertNil(SwitcherInputMode.eventTap.statusMenuWarning(alternateForced: false,
                                                                      accessibilityTrusted: trusted))
            XCTAssertFalse(SwitcherInputMode.eventTap.showsAccessibilityAction(alternateForced: false,
                                                                               accessibilityTrusted: trusted))
        }
    }

    func testPauseIsAlreadyExplainedByTheMenu() {
        XCTAssertNil(SwitcherInputMode.paused.statusMenuWarning(alternateForced: false,
                                                                accessibilityTrusted: false))
        XCTAssertFalse(SwitcherInputMode.paused.showsAccessibilityAction(alternateForced: false,
                                                                         accessibilityTrusted: false))
    }

    /// The case #96 exists for: Accessibility is missing, so Zap is on ⌥-Tab
    /// without the user having asked for it.
    func testMissingAccessibilityFallbackPointsAtAccessibilityAndShowsTheAction() throws {
        let warning = try XCTUnwrap(SwitcherInputMode.fallback.statusMenuWarning(alternateForced: false,
                                                                                 accessibilityTrusted: false))
        XCTAssertTrue(warning.contains("⌥-Tab"))
        XCTAssertTrue(warning.contains("Accessibility"))
        XCTAssertFalse(warning.contains("event tap"))
        XCTAssertTrue(SwitcherInputMode.fallback.showsAccessibilityAction(alternateForced: false,
                                                                          accessibilityTrusted: false))
    }

    func testChosenFallbackIsNotAWarning() {
        for trusted in [false, true] {
            XCTAssertNil(SwitcherInputMode.fallback.statusMenuWarning(alternateForced: true,
                                                                      accessibilityTrusted: trusted))
            XCTAssertFalse(SwitcherInputMode.fallback.showsAccessibilityAction(alternateForced: true,
                                                                               accessibilityTrusted: trusted))
        }
    }

    /// Trust is already granted, so the event tap itself failed. Blaming
    /// Accessibility, and offering its settings pane, would be misleading.
    func testTrustedEventTapFailureDoesNotBlameAccessibility() throws {
        let warning = try XCTUnwrap(SwitcherInputMode.fallback.statusMenuWarning(alternateForced: false,
                                                                                 accessibilityTrusted: true))
        XCTAssertTrue(warning.contains("⌥-Tab"))
        XCTAssertTrue(warning.contains("event tap"))
        XCTAssertFalse(warning.contains("Accessibility"))
        XCTAssertFalse(SwitcherInputMode.fallback.showsAccessibilityAction(alternateForced: false,
                                                                           accessibilityTrusted: true))
    }

    /// The user deliberately chose ⌥-Tab and its registration failed. ⌘-Tab
    /// was never attempted, so the warning must not blame it, and Accessibility
    /// is not the fix.
    func testDeliberateOptionTabRegistrationFailureDoesNotBlameCommandLineOrOfferAccessibility() throws {
        for trusted in [false, true] {
            let warning = try XCTUnwrap(SwitcherInputMode.unavailable.statusMenuWarning(alternateForced: true,
                                                                                         accessibilityTrusted: trusted))
            XCTAssertTrue(warning.contains("⌥-Tab"))
            XCTAssertFalse(warning.contains("⌘-Tab"))
            XCTAssertFalse(warning.contains("Accessibility"))
            XCTAssertFalse(SwitcherInputMode.unavailable.showsAccessibilityAction(alternateForced: true,
                                                                                   accessibilityTrusted: trusted))
        }
    }

    func testMissingAccessibilityWithFailedFallbackStillOffersTheAction() throws {
        let warning = try XCTUnwrap(SwitcherInputMode.unavailable.statusMenuWarning(alternateForced: false,
                                                                                    accessibilityTrusted: false))
        XCTAssertTrue(warning.contains("Accessibility"))
        XCTAssertTrue(SwitcherInputMode.unavailable.showsAccessibilityAction(alternateForced: false,
                                                                             accessibilityTrusted: false))
    }

    func testTrustedEventTapAndFallbackFailureHidesTheAction() throws {
        let warning = try XCTUnwrap(SwitcherInputMode.unavailable.statusMenuWarning(alternateForced: false,
                                                                                    accessibilityTrusted: true))
        XCTAssertTrue(warning.contains("event tap"))
        XCTAssertFalse(warning.contains("Accessibility"))
        XCTAssertFalse(SwitcherInputMode.unavailable.showsAccessibilityAction(alternateForced: false,
                                                                              accessibilityTrusted: true))
    }
}

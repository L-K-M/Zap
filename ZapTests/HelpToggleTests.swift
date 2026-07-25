import XCTest
@testable import Zap

/// The key that toggles the in-switcher key hints
/// (`EventTapMonitor.togglesHelp(shiftedCharacter:)`).
final class HelpToggleTests: XCTestCase {

    func testQuestionMarkToggles() {
        XCTAssertTrue(EventTapMonitor.togglesHelp(shiftedCharacter: "?"))
    }

    func testUnshiftedTwinsDoNotToggle() {
        // The rule reads the key *with Shift honoured*, so the unshifted glyph of
        // the "?" key — which differs per layout ("/" on US, "ß" on QWERTZ, "," on
        // AZERTY) — never has to be recognised, and never triggers by itself.
        for character: Character in ["/", "ß", ",", "-"] {
            XCTAssertFalse(EventTapMonitor.togglesHelp(shiftedCharacter: character))
        }
    }

    func testLettersDigitsAndSpaceDoNotToggle() {
        for character: Character in ["a", "z", "Q", "1", "9", " ", "."] {
            XCTAssertFalse(EventTapMonitor.togglesHelp(shiftedCharacter: character),
                           "\(character) should reach type-to-search, not the hints")
        }
    }

    func testKeyThatTypesNothingDoesNotToggle() {
        XCTAssertFalse(EventTapMonitor.togglesHelp(shiftedCharacter: nil))
    }

    func testHelpKeyIsNotASearchCharacter() {
        // The toggle is only free because the search query ignores punctuation:
        // if that ever changes, "?" would start typing instead of toggling.
        let questionMark: Character = "?"
        XCTAssertFalse(questionMark.isLetter || questionMark.isNumber || questionMark == " ")
    }
}

/// Which keys the hints footer advertises in each state
/// (`OverlayView.helpHints(windowsShown:windowFocused:windowListEnabled:)`).
final class HelpHintsTests: XCTestCase {

    private func hints(windowsShown: Bool, windowFocused: Bool,
                       windowListEnabled: Bool = true) -> [String] {
        OverlayView.helpHints(windowsShown: windowsShown,
                              windowFocused: windowFocused,
                              windowListEnabled: windowListEnabled)
    }

    func testAppRowKeysAreAlwaysListed() {
        for shown in [true, false] {
            let listed = hints(windowsShown: shown, windowFocused: false)
            XCTAssertTrue(listed.contains { $0.contains("next") })
            XCTAssertTrue(listed.contains { $0.contains("type to search") })
            XCTAssertTrue(listed.contains { $0.contains("quit") })
            XCTAssertTrue(listed.contains { $0.contains("hide") })
            XCTAssertTrue(listed.contains { $0.contains("esc") })
        }
    }

    func testCloseWindowOnlyAppearsWithAFocusedWindow() {
        XCTAssertFalse(hints(windowsShown: false, windowFocused: false)
            .contains { $0.contains("close") })
        XCTAssertFalse(hints(windowsShown: true, windowFocused: false)
            .contains { $0.contains("close") })
        XCTAssertTrue(hints(windowsShown: true, windowFocused: true)
            .contains { $0.contains("close") })
    }

    func testWindowListIsOfferedOnceItIsOnScreen() {
        XCTAssertTrue(hints(windowsShown: true, windowFocused: false)
            .contains { $0.contains("windows") })
    }

    func testDwellHintOnlyWhenTheWindowListCanAppear() {
        XCTAssertTrue(hints(windowsShown: false, windowFocused: false,
                            windowListEnabled: true)
            .contains { $0.contains("pause for windows") })
        XCTAssertFalse(hints(windowsShown: false, windowFocused: false,
                             windowListEnabled: false)
            .contains { $0.contains("pause for windows") })
    }

    func testHintsAlwaysExplainHowToDismissThemselves() {
        for (shown, focused) in [(false, false), (true, false), (true, true)] {
            XCTAssertTrue(hints(windowsShown: shown, windowFocused: focused)
                .contains { $0.contains("hide hints") })
        }
    }
}

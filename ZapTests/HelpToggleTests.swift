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

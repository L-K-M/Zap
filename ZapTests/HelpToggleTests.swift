import XCTest
@testable import Zap

/// The key that toggles the in-switcher key hints
/// (`SwitcherController.togglesHelp(_:)`).
final class HelpToggleTests: XCTestCase {

    func testQuestionMarkToggles() {
        XCTAssertTrue(SwitcherController.togglesHelp("?"))
    }

    func testSlashTogglesToo() {
        // The event tap clears modifiers before translating the key, so pressing
        // ⇧/ ("?" on most layouts) arrives as "/". Both must work or the hint key
        // would do nothing on a US keyboard.
        XCTAssertTrue(SwitcherController.togglesHelp("/"))
    }

    func testLettersDigitsAndSpaceDoNotToggle() {
        for character in ["a", "z", "Q", "1", "9", " ", ".", "-"] {
            XCTAssertFalse(SwitcherController.togglesHelp(Character(character)),
                           "\(character) should reach type-to-search, not the hints")
        }
    }

    func testHelpKeyIsNotASearchCharacter() {
        // The toggle is only free because the search query ignores punctuation:
        // if that ever changes, "?" would start typing instead of toggling.
        for character in ["?", "/"] {
            let scalar = Character(character)
            XCTAssertFalse(scalar.isLetter || scalar.isNumber || scalar == " ")
        }
    }
}

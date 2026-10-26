import XCTest
@testable import Zap

/// The number-key shortcut rule (see
/// `SwitcherController.numberJumpIndex(for:currentQuery:names:)`).
///
/// A leading digit is a jump-and-commit shortcut *unless* a visible app name
/// starts with that digit — then the digit is ordinary search text, so apps like
/// "1Password" stay reachable by typing (mimo.md §1 / ANALYSIS.md B6).
final class NumberJumpTests: XCTestCase {

    private let names = ["Safari", "Terminal", "Mail", "Notes", "Music"]

    // MARK: Jumping

    func testLeadingDigitJumpsWhenNoNameStartsWithIt() {
        XCTAssertEqual(SwitcherController.numberJumpIndex(for: "2", currentQuery: "", names: names), 1)
        XCTAssertEqual(SwitcherController.numberJumpIndex(for: "5", currentQuery: "", names: names), 4)
    }

    func testJumpIndexIsZeroBasedPositionInVisibleList() {
        XCTAssertEqual(SwitcherController.numberJumpIndex(for: "1", currentQuery: "", names: names), 0)
    }

    // MARK: Search beats jump

    func testDigitIsSearchTextWhenAnAppNameStartsWithIt() {
        let names = ["1Password", "Safari", "Mail"]
        XCTAssertNil(SwitcherController.numberJumpIndex(for: "1", currentQuery: "", names: names))
    }

    func testDigitJumpsWhenNoVisibleAppNameStartsWithIt() {
        // The name check is over the visible list only: with "1Password"
        // excluded (not visible), digit 1 jumps again.
        XCTAssertEqual(SwitcherController.numberJumpIndex(for: "1", currentQuery: "", names: ["Safari", "Mail"]), 0)
    }

    func testDigitMidNameDoesNotBlockTheJump() {
        // Prefix, not containment: "Photos 3" and "Deckset" must not suppress
        // the jumps for 3 and 1. Swapping hasPrefix for contains would pass
        // every other test in this file and break this one.
        XCTAssertEqual(SwitcherController.numberJumpIndex(for: "3", currentQuery: "", names: ["Safari", "Mail", "Photos 3"]), 2)
        XCTAssertEqual(SwitcherController.numberJumpIndex(for: "1", currentQuery: "", names: ["Deckset", "Mail"]), 0)
    }

    // MARK: Not jumps

    func testDigitWithNoSuchAppIsNotAJump() {
        XCTAssertNil(SwitcherController.numberJumpIndex(for: "9", currentQuery: "", names: names))
    }

    func testZeroIsNotAJump() {
        XCTAssertNil(SwitcherController.numberJumpIndex(for: "0", currentQuery: "", names: names))
    }

    func testDigitIsSearchTextWhenAQueryIsAlreadyTyped() {
        // "vi2" is a search refinement, not a jump.
        XCTAssertNil(SwitcherController.numberJumpIndex(for: "2", currentQuery: "vi", names: names))
    }

    func testLetterIsNeverAJump() {
        XCTAssertNil(SwitcherController.numberJumpIndex(for: "s", currentQuery: "", names: names))
    }

    func testEmptyListHasNoJump() {
        XCTAssertNil(SwitcherController.numberJumpIndex(for: "1", currentQuery: "", names: []))
    }
}

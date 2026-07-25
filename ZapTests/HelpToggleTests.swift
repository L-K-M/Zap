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
        // Documents the *premise* that made "?" available to take — the search
        // query accepts only letters, digits and spaces — not the routing, which
        // is the tap checking togglesHelp before forwarding a typed character.
        // If the query ever accepted punctuation, "?" would stop being free.
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
        // Every reachable state, including a focused window — the branch that adds
        // the move/close hints must not quietly take a base key with it.
        for (shown, focused) in [(false, false), (true, false), (true, true)] {
            let listed = hints(windowsShown: shown, windowFocused: focused)
            XCTAssertTrue(listed.contains { $0.contains("next") })
            XCTAssertTrue(listed.contains { $0.contains("type to search") })
            // Match the key, not the verb: "hide" alone would also be satisfied
            // by the always-present "? hide hints" entry.
            XCTAssertTrue(listed.contains { $0.contains("⌘Q") })
            XCTAssertTrue(listed.contains { $0.contains("⌘H") })
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

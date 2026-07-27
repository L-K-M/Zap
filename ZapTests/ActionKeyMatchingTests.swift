import XCTest
@testable import Zap

/// Character-based matching of the in-switcher action keys
/// (`EventTapMonitor.shortcutKey(for:)`), which is what makes ⌘Q/⌘H/⌘W land on
/// the right physical key on non-QWERTY layouts.
final class ActionKeyMatchingTests: XCTestCase {

    func testLettersMapToTheirActions() {
        XCTAssertEqual(EventTapMonitor.shortcutKey(for: "q"), .quit)
        XCTAssertEqual(EventTapMonitor.shortcutKey(for: "h"), .hide)
        XCTAssertEqual(EventTapMonitor.shortcutKey(for: "w"), .closeWindow)
    }

    func testMatchingIsCaseInsensitive() {
        // The event's flags are cleared before translation, so an uppercase
        // reading shouldn't occur — but a layout that reports one must still work.
        XCTAssertEqual(EventTapMonitor.shortcutKey(for: "Q"), .quit)
        XCTAssertEqual(EventTapMonitor.shortcutKey(for: "H"), .hide)
        XCTAssertEqual(EventTapMonitor.shortcutKey(for: "W"), .closeWindow)
    }

    func testOtherCharactersAreOrdinaryLetters() {
        XCTAssertNil(EventTapMonitor.shortcutKey(for: "a"))
        XCTAssertNil(EventTapMonitor.shortcutKey(for: "z"))
        XCTAssertNil(EventTapMonitor.shortcutKey(for: "1"))
        XCTAssertNil(EventTapMonitor.shortcutKey(for: " "))
        XCTAssertNil(EventTapMonitor.shortcutKey(for: "é"))
    }

    func testKeyWithNoTextIsNotAnActionKey() {
        // Function keys and the like produce no character at all.
        XCTAssertNil(EventTapMonitor.shortcutKey(for: nil))
    }
}

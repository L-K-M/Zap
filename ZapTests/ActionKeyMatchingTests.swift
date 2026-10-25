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

    // MARK: Key-up consumption

    func testKeyUpFollowsItsConsumedKeyDown() {
        // A recorded dual-purpose key was swallowed on the way down whatever
        // happened since; its release must be swallowed too.
        XCTAssertTrue(EventTapMonitor.shouldConsumeKeyUp(recordedShortcutKey: true,
                                                         isSwitching: true))
        XCTAssertTrue(EventTapMonitor.shouldConsumeKeyUp(recordedShortcutKey: true,
                                                         isSwitching: false))
    }

    func testKeyUpDuringALiveSessionIsSwallowed() {
        // While a session is up every key-down is swallowed, releases included.
        XCTAssertTrue(EventTapMonitor.shouldConsumeKeyUp(recordedShortcutKey: false,
                                                         isSwitching: true))
    }

    func testUnrelatedKeyUpOutsideASessionPassesThrough() {
        XCTAssertFalse(EventTapMonitor.shouldConsumeKeyUp(recordedShortcutKey: false,
                                                          isSwitching: false))
    }
}

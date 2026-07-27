import XCTest
@testable import Zap

final class TypeToSearchTests: XCTestCase {

    func testEmptyQueryMatchesNothing() {
        XCTAssertNil(SwitcherController.bestMatchIndex(query: "", names: ["Safari", "Mail"]))
    }

    func testPrefixMatchIsPreferred() {
        let names = ["Finder", "Safari", "System Settings"]
        XCTAssertEqual(SwitcherController.bestMatchIndex(query: "saf", names: names), 1)
    }

    func testEarliestPrefixWinsOverLaterOne() {
        // Both start with "te"; the earliest (MRU-first) one is chosen.
        let names = ["TextEdit", "Terminal"]
        XCTAssertEqual(SwitcherController.bestMatchIndex(query: "te", names: names), 0)
    }

    func testMatchingIsCaseInsensitive() {
        let names = ["Safari", "Mail"]
        XCTAssertEqual(SwitcherController.bestMatchIndex(query: "MA", names: names), 1)
    }

    func testWordPrefixBeatsSubstring() {
        // "co" appears mid-word in "Discord" (substring) but starts the word "Code"
        // in "Visual Studio Code" — the word-prefix match is preferred.
        let names = ["Discord", "Visual Studio Code"]
        XCTAssertEqual(SwitcherController.bestMatchIndex(query: "co", names: names), 1)
    }

    func testSubstringFallbackWhenNoPrefix() {
        let names = ["Safari", "Reminders"]
        // "mind" is a substring of "Reminders" only.
        XCTAssertEqual(SwitcherController.bestMatchIndex(query: "mind", names: names), 1)
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(SwitcherController.bestMatchIndex(query: "zzz", names: ["Safari", "Mail"]))
    }

    func testFullPrefixOverWordPrefixEvenWhenLater() {
        // "sl" prefixes the *word* "Slack" inside index 0 (word-prefix) and the
        // *whole name* at index 1 (prefix). The whole-name prefix wins even though
        // it comes later in the list.
        let names = ["Microsoft Slack Bridge", "Slack"]
        XCTAssertEqual(SwitcherController.bestMatchIndex(query: "sl", names: names), 1)
    }

    // MARK: Subsequence (fuzzy) tier

    func testInitialsMatchAsASubsequence() {
        // The way people actually type a multi-word app name in a hurry.
        let names = ["Finder", "Visual Studio Code"]
        XCTAssertEqual(SwitcherController.bestMatchIndex(query: "vsc", names: names), 1)
    }

    func testSubsequenceSpansWords() {
        let names = ["Safari", "Microsoft PowerPoint"]
        XCTAssertEqual(SwitcherController.bestMatchIndex(query: "ppt", names: names), 1)
    }

    func testSubstringStillBeatsSubsequence() {
        // "sci" is a subsequence of "Slack Client" (index 0) but a substring of
        // "Viscid" (index 1); the higher tier wins even though it comes later.
        let names = ["Slack Client", "Viscid"]
        XCTAssertEqual(SwitcherController.bestMatchIndex(query: "sci", names: names), 1)
    }

    func testEarliestSubsequenceWins() {
        let names = ["Visual Studio Code", "Very Small Calculator"]
        XCTAssertEqual(SwitcherController.bestMatchIndex(query: "vsc", names: names), 0)
    }

    func testOutOfOrderCharactersDoNotMatch() {
        // A subsequence must appear in order — "csv" is not "Visual Studio Code".
        XCTAssertNil(SwitcherController.bestMatchIndex(query: "csv", names: ["Visual Studio Code"]))
    }

    func testSubsequenceHelper() {
        XCTAssertTrue(SwitcherController.isSubsequence("vsc", of: "visual studio code"))
        XCTAssertTrue(SwitcherController.isSubsequence("mail", of: "mail"))
        XCTAssertFalse(SwitcherController.isSubsequence("mailx", of: "mail"))
        XCTAssertFalse(SwitcherController.isSubsequence("zz", of: "zap"))
    }
}

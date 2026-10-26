import XCTest
@testable import Zap

final class TypeToSearchTests: XCTestCase {

    func testEmptyQueryMatchesNothing() {
        XCTAssertNil(SwitcherController.bestMatchIndex(query: "", names: ["Safari", "Mail"]))
    }

    // MARK: selectableMatch

    private func app(_ id: String, pid: pid_t) -> AppInfo {
        AppInfo(bundleIdentifier: id, name: id, processIdentifier: pid)
    }

    func testMatchSkipsAppsPendingQuit() {
        // "quick" names QuickTime, but while it is dimmed and unselectable the
        // query must report a miss rather than claim a match the highlight
        // cannot take.
        let apps = [app("QuickTime", pid: 1), app("Safari", pid: 2)]
        XCTAssertNil(SwitcherController.selectableMatch(query: "quick", apps: apps,
                                                        quittingPIDs: [1]))
        XCTAssertEqual(SwitcherController.selectableMatch(query: "saf", apps: apps,
                                                          quittingPIDs: [1]), 1)
    }

    func testEmptyQueryMatchesNothingSelectable() {
        // No query, no jump: the badge must report the miss rather than the
        // highlight snapping somewhere arbitrary.
        let apps = [app("Safari", pid: 1)]
        XCTAssertNil(SwitcherController.selectableMatch(query: "", apps: apps,
                                                        quittingPIDs: []))
    }

    func testMatchSkipsMultiplePendingQuitApps() {
        // The offset remap must survive skipping more than one dimmed app: the
        // returned index refers to `apps`, not to the filtered candidate list.
        let apps = [app("Mail", pid: 1), app("Maps", pid: 2), app("Music", pid: 3)]
        XCTAssertEqual(SwitcherController.selectableMatch(query: "mu", apps: apps,
                                                          quittingPIDs: [1, 2]), 2)
    }

    func testMatchReturnsNilWhenEveryCandidateIsQuitting() {
        // Nothing is choosable, so there is nothing to point at — a stale or
        // out-of-range index here would highlight the wrong row.
        let apps = [app("Mail", pid: 1), app("Music", pid: 2)]
        XCTAssertNil(SwitcherController.selectableMatch(query: "m", apps: apps,
                                                        quittingPIDs: [1, 2]))
    }

    func testMatchReturnsNilForEmptyApps() {
        XCTAssertNil(SwitcherController.selectableMatch(query: "saf", apps: [],
                                                        quittingPIDs: []))
    }

    func testMatchFallsThroughToTheNextSelectableCandidate() {
        // "m" prefix-matches Mail (index 0, quitting); the best *selectable*
        // match is Music, and the returned index is the one the highlight uses.
        let apps = [app("Mail", pid: 1), app("Music", pid: 2)]
        XCTAssertEqual(SwitcherController.selectableMatch(query: "m", apps: apps,
                                                          quittingPIDs: [1]), 1)
    }

    func testMatchPreservesOriginalIndices() {
        let apps = [app("a", pid: 1), app("Terminal", pid: 2), app("c", pid: 3)]
        XCTAssertEqual(SwitcherController.selectableMatch(query: "term", apps: apps,
                                                          quittingPIDs: [1]), 1)
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

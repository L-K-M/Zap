import Foundation
import XCTest
@testable import Zap

/// Matching a Mac app to an icon in a Linux theme (`UNJAILED.md §5.6`).
///
/// The naming is the whole difficulty of icon sets, so these are the cases the
/// design note calls out by name plus the ones that made it wrong on the way.
final class IconNameGuessTests: XCTestCase {

    // MARK: Normalising

    func testNormalisingLowercasesAndHyphenates() {
        XCTAssertEqual(IconNameGuess.normalised("Google Chrome"), "google-chrome")
        XCTAssertEqual(IconNameGuess.normalised("Visual Studio Code"), "visual-studio-code")
    }

    /// The case that made this function exist: a trailing separator would miss
    /// every icon in the theme.
    func testNormalisingTrimsTrailingSeparators() {
        XCTAssertEqual(IconNameGuess.normalised("Claude ★"), "claude")
        XCTAssertEqual(IconNameGuess.normalised("  Slack  "), "slack")
    }

    func testNormalisingCollapsesRunsOfPunctuation() {
        XCTAssertEqual(IconNameGuess.normalised("Adobe — Photoshop (2026)"), "adobe-photoshop-2026")
    }

    func testNormalisingDropsNonASCIIRatherThanTransliterating() {
        // Themes name files in ASCII, so anything else can only be noise here.
        XCTAssertEqual(IconNameGuess.normalised("Übersicht"), "bersicht")
    }

    // MARK: Candidates

    func testCandidatesIncludeTheVendorlessSpelling() {
        let candidates = IconNameGuess.candidates(appName: "Google Chrome",
                                                  bundleIdentifier: "com.google.Chrome")
        XCTAssertEqual(candidates.first, "google-chrome")
        XCTAssertTrue(candidates.contains("chrome"))
    }

    func testCandidatesIncludeTheIdentifierTail() {
        let candidates = IconNameGuess.candidates(appName: "Safari",
                                                  bundleIdentifier: "com.apple.Safari")
        XCTAssertTrue(candidates.contains("safari"))
    }

    /// Settings lists apps that aren't running out of manifest keys, and those keys
    /// are bundle *paths*. Every path's last dot-component is `app`, so taking the
    /// tail from one would suggest whatever the theme calls `app` for every single
    /// offline row.
    func testCandidatesIgnoreAPathShapedIdentifier() {
        let candidates = IconNameGuess.candidates(
            appName: "Claude ★", bundleIdentifier: "/Applications/Claude ★.app")
        XCTAssertEqual(candidates, ["claude"])
        XCTAssertFalse(candidates.contains("app"))
    }

    func testCandidatesAreDeduplicated() {
        let candidates = IconNameGuess.candidates(appName: "Slack",
                                                  bundleIdentifier: "com.slack.Slack")
        XCTAssertEqual(candidates, ["slack"])
    }

    // MARK: Matching

    private let theme: Set<String> = [
        "google-chrome", "chrome", "firefox", "slack", "docker", "docker-compose",
        "visual-studio-code", "code", "safari", "spotify", "utilities-terminal",
        "mail-client", "app",
    ]

    func testAnExactNameWins() {
        let matches = IconNameGuess.matches(appName: "Firefox",
                                            bundleIdentifier: "org.mozilla.firefox", in: theme)
        XCTAssertEqual(matches.first?.iconName, "firefox")
    }

    /// The row `UNJAILED.md §5.6` marks ❌: close, and wrong without help.
    func testDockerDesktopFindsDocker() {
        let matches = IconNameGuess.matches(appName: "Docker Desktop",
                                            bundleIdentifier: "com.docker.docker", in: theme)
        XCTAssertEqual(matches.first?.iconName, "docker")
    }

    /// The other ❌ row: the identifier says nothing useful, so only the alias table
    /// reaches it.
    func testSlackIsFoundThroughItsAlias() {
        let matches = IconNameGuess.matches(appName: "Slack for Teams",
                                            bundleIdentifier: "com.tinyspeck.slackmacgap", in: theme)
        XCTAssertEqual(matches.first?.iconName, "slack")
        XCTAssertEqual(matches.first?.confidence, .known)
    }

    func testMatchesAreRankedByConfidence() {
        let matches = IconNameGuess.matches(appName: "Docker Desktop",
                                            bundleIdentifier: "com.docker.docker", in: theme)
        let confidences = matches.map(\.confidence)
        XCTAssertEqual(confidences, confidences.sorted(by: >))
    }

    func testMatchesNeverRepeatAnIconName() {
        let matches = IconNameGuess.matches(appName: "Google Chrome",
                                            bundleIdentifier: "com.google.Chrome", in: theme)
        XCTAssertEqual(Set(matches.map(\.iconName)).count, matches.count)
    }

    func testMatchesRespectTheLimit() {
        let matches = IconNameGuess.matches(appName: "Docker Desktop",
                                            bundleIdentifier: "com.docker.docker",
                                            in: theme, limit: 1)
        XCTAssertEqual(matches.count, 1)
    }

    /// A miss costs nothing — the user is already in the picker — but it must be a
    /// miss rather than a confident wrong answer.
    func testAnUnknownAppSuggestsNothing() {
        let matches = IconNameGuess.matches(appName: "Zap",
                                            bundleIdentifier: "ch.lkmc.Zap", in: theme)
        XCTAssertTrue(matches.isEmpty)
    }

    /// Suggestions are drawn from the installed theme, never invented: an alias
    /// naming an icon the set doesn't ship must not be offered.
    func testAliasesAreFilteredAgainstTheInstalledSet() {
        let matches = IconNameGuess.matches(appName: "Safari",
                                            bundleIdentifier: "com.apple.Safari",
                                            in: ["safari"])
        XCTAssertEqual(matches.map(\.iconName), ["safari"])
    }

    /// A theme name that *extends* the app's is a match; one that merely starts
    /// with the same letters is not. The hyphen is the word boundary, and it is the
    /// only thing separating `blender-symbolic` from `blenderx`.
    func testAnIconExtendingTheAppNameMatchesOnlyAtAWordBoundary() {
        let matches = IconNameGuess.matches(appName: "Blender",
                                            bundleIdentifier: "org.blender",
                                            in: ["blender-symbolic", "blenderx"])
        XCTAssertEqual(matches.map(\.iconName), ["blender-symbolic"])
        XCTAssertEqual(matches.first?.confidence, .prefix)
    }

    /// The weakest tier matches on a word the two names share, which for short
    /// words would drag in half a theme — so it takes only words of substance.
    ///
    /// Both halves use an interior word, which is the only position no other tier
    /// can reach: a leading word is already a candidate spelling of its own.
    func testTheWeakestTierIgnoresShortWords() {
        XCTAssertTrue(IconNameGuess.matches(appName: "Corel Paint Ink Studio",
                                            bundleIdentifier: "com.corel.painter",
                                            in: ["ink"]).isEmpty)
        let matches = IconNameGuess.matches(appName: "Corel Paint Ink Studio",
                                            bundleIdentifier: "com.corel.painter",
                                            in: ["studio"])
        XCTAssertEqual(matches.map(\.iconName), ["studio"])
        XCTAssertEqual(matches.first?.confidence, .related)
    }
}

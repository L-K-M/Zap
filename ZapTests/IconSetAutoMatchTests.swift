import Foundation
import XCTest
@testable import Zap

/// Which matches are strong enough to apply to every app at once, with nobody
/// looking at the result (`IconSetAutoMatch`).
final class IconSetAutoMatchTests: XCTestCase {

    /// A theme with the shapes that matter: names that match exactly, names that
    /// only *extend* an app's name, and names that merely share a word.
    private let theme: Set<String> = [
        "firefox", "google-chrome", "docker", "slack", "spotify",
        "chrome-remote-desktop", "ada-lovelace", "photoshop", "studio",
    ]

    // MARK: The bar

    func testAppliesAnExactName() {
        XCTAssertEqual(IconSetAutoMatch.confidentMatch(appName: "Firefox",
                                                       bundleIdentifier: "org.example.ff",
                                                       in: theme),
                       "firefox")
    }

    /// A hand-written alias is the strongest signal there is — someone decided it.
    func testAppliesAKnownAlias() {
        XCTAssertEqual(IconSetAutoMatch.confidentMatch(appName: "Slack for Teams",
                                                       bundleIdentifier: "com.tinyspeck.slackmacgap",
                                                       in: theme),
                       "slack")
    }

    /// The exclusion that matters. `.prefix` finds `docker` for "Docker Desktop",
    /// which is right — and `chrome-remote-desktop` for an app called Chrome when
    /// the theme has no `chrome`, which is not. Right-more-often-than-not is a good
    /// suggestion and a bad automatic action, so bulk takes neither.
    func testDoesNotApplyAWordBoundaryPrefix() {
        XCTAssertNil(IconSetAutoMatch.confidentMatch(appName: "Chrome",
                                                     bundleIdentifier: "org.example.chrome",
                                                     in: ["chrome-remote-desktop"]))
        XCTAssertNil(IconSetAutoMatch.confidentMatch(appName: "Ada",
                                                     bundleIdentifier: "org.example.ada",
                                                     in: ["ada-lovelace"]))
    }

    func testDoesNotApplyAMerelyRelatedName() {
        // `studio` is a word of the app's name and an icon in the theme; the
        // picker would offer it, and it is nothing like this app.
        XCTAssertNil(IconSetAutoMatch.confidentMatch(appName: "Corel Paint Ink Studio",
                                                     bundleIdentifier: "com.corel.painter",
                                                     in: theme))
    }

    func testAppliesNothingWhenTheSetHasNothing() {
        XCTAssertNil(IconSetAutoMatch.confidentMatch(appName: "Zap",
                                                     bundleIdentifier: "ch.lkmc.Zap",
                                                     in: theme))
    }

    /// The tiers, stated directly, so a future reordering of `Confidence` can't
    /// quietly move the bar.
    func testOnlyTheTopTwoTiersAreConfident() {
        XCTAssertTrue(IconSetAutoMatch.isConfident(.known))
        XCTAssertTrue(IconSetAutoMatch.isConfident(.exact))
        XCTAssertFalse(IconSetAutoMatch.isConfident(.prefix))
        XCTAssertFalse(IconSetAutoMatch.isConfident(.related))
    }

    /// An exact match must win even when a weaker one sorts alongside it — the
    /// implementation only inspects the head of the ranked list, which is only
    /// sound while the ranking really does put the strongest first.
    func testAnExactNameWinsOverAWeakerNeighbour() {
        XCTAssertEqual(IconSetAutoMatch.confidentMatch(appName: "Chrome",
                                                       bundleIdentifier: "org.example.chrome",
                                                       in: ["chrome", "chrome-remote-desktop"]),
                       "chrome")
    }

    // MARK: Summary

    func testSummaryLeadsWithWhatChanged() {
        let summary = IconSetAutoMatch.summary(
            .init(applied: 12, unmatched: 3, skipped: 2, failed: 0), setName: "Papirus")
        XCTAssertTrue(summary.hasPrefix("Applied 12 icons from Papirus."), summary)
        XCTAssertTrue(summary.contains("2 apps kept"), summary)
        XCTAssertTrue(summary.contains("3 apps had no confident match"), summary)
        XCTAssertFalse(summary.contains("rendered"), "nothing failed, so don't mention it")
    }

    /// "Nothing happened" is the outcome most in need of an explanation, and the
    /// usual reason is that every app already carried the user's own choice.
    func testSummaryExplainsAnEmptyRun() {
        let summary = IconSetAutoMatch.summary(
            .init(applied: 0, unmatched: 0, skipped: 7, failed: 0), setName: "Tela")
        XCTAssertTrue(summary.hasPrefix("Applied 0 icons from Tela."), summary)
        XCTAssertTrue(summary.contains("7 apps kept the icons you'd already given them"), summary)
    }

    func testSummarySingularisesCounts() {
        let summary = IconSetAutoMatch.summary(
            .init(applied: 1, unmatched: 1, skipped: 1, failed: 1), setName: "Breeze")
        XCTAssertTrue(summary.contains("Applied 1 icon from Breeze."), summary)
        XCTAssertTrue(summary.contains("1 app kept the icon"), summary)
        XCTAssertTrue(summary.contains("1 app had no confident match"), summary)
        XCTAssertTrue(summary.contains("1 icon couldn't be rendered"), summary)
    }
}

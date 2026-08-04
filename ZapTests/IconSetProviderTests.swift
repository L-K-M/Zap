import Foundation
import XCTest
@testable import Zap

/// An installed theme as something the search sheet can search (`UNJAILED.md §5.6`).
final class IconSetProviderTests: XCTestCase {

    private var directory: URL!

    private let set = IconSet(
        id: "testset", name: "Test Set", summary: "A set built by the tests.",
        owner: "example", repository: "theme",
        branch: "main", license: "CC0-1.0",
        licenseURL: URL(string: "https://example.invalid/licence"),
        homepage: URL(string: "https://example.invalid/"),
        archiveGlob: "*/apps/*.svg", strippedComponents: 2)

    private let names: Set<String> = [
        "firefox", "firefox-nightly", "google-chrome", "chrome", "slack", "docker",
        "mail", "mail-client-list", "internet-mail", "utilities-terminal",
    ]

    override func setUp() {
        super.setUp()
        directory = IconTestSupport.makeTemporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    private func makeProvider() -> IconSetProvider {
        IconSetProvider(iconSet: set, directory: directory, iconNames: names)
    }

    // MARK: Provider surface

    /// The one provider with nothing to disclose, because it sends nothing. §5.5's
    /// wall exists to be read; putting one in front of a local search teaches people
    /// to click through the ones that matter.
    func testALocalSetDisclosesNothing() {
        XCTAssertNil(makeProvider().disclosure)
        XCTAssertFalse(makeProvider().requiresAPIKey)
    }

    func testResultsCarryTheSetsAttribution() throws {
        let result = try XCTUnwrap(makeProvider().result(forIconName: "firefox"))
        XCTAssertEqual(result.providerID, "testset")
        XCTAssertEqual(result.credit, "Test Set")
        XCTAssertEqual(result.license, "CC0-1.0")
        XCTAssertEqual(result.title, "firefox")
        XCTAssertTrue(result.isVector)
    }

    func testHyphensBecomeSpacesInTheTitle() throws {
        let result = try XCTUnwrap(makeProvider().result(forIconName: "google-chrome"))
        XCTAssertEqual(result.title, "google chrome")
    }

    /// A name the path check refuses produces no result at all, rather than one
    /// carrying a URL that points at the set's directory instead of an icon.
    func testANameThatCannotBeResolvedProducesNoResult() {
        XCTAssertNil(makeProvider().result(forIconName: "../escape"))
    }

    /// The artwork's real location, not the folder it lives in.
    func testAResultPointsAtItsOwnFile() throws {
        let result = try XCTUnwrap(makeProvider().result(forIconName: "firefox"))
        XCTAssertEqual(result.imageURL.lastPathComponent, "firefox.svg")
    }

    // MARK: Ranking

    func testAnExactNameRanksFirst() {
        XCTAssertEqual(IconSetProvider.ranked(query: "firefox", in: names, limit: 5).first, "firefox")
    }

    func testExactBeatsPrefixBeatsSubstring() {
        let ranked = IconSetProvider.ranked(query: "mail", in: names, limit: 5)
        XCTAssertEqual(ranked, ["mail", "mail-client-list", "internet-mail"])
    }

    func testTiesBreakOnLengthThenAlphabetically() {
        let ranked = IconSetProvider.ranked(query: "c", in: ["cd", "cc", "ccc"], limit: 5)
        XCTAssertEqual(ranked, ["cc", "cd", "ccc"])
    }

    /// A typed query is normalised the same way an app name is, so searching
    /// "Google Chrome" finds `google-chrome` rather than nothing.
    func testTheQueryIsNormalisedLikeAnAppName() {
        XCTAssertEqual(IconSetProvider.ranked(query: "Google Chrome", in: names, limit: 5).first,
                       "google-chrome")
    }

    func testAnEmptyQueryMatchesNothing() {
        XCTAssertTrue(IconSetProvider.ranked(query: "   ", in: names, limit: 5).isEmpty)
        XCTAssertTrue(IconSetProvider.ranked(query: "firefox", in: names, limit: 0).isEmpty)
    }

    func testRankingRespectsTheLimit() {
        XCTAssertEqual(IconSetProvider.ranked(query: "f", in: names, limit: 1).count, 1)
    }

    // MARK: Suggestions

    func testSuggestionsComeFromTheGuesser() async {
        let suggestions = await makeProvider().suggestions(
            appName: "Docker Desktop", bundleIdentifier: "com.docker.docker", limit: 5)
        XCTAssertEqual(suggestions.first?.title, "docker")
        XCTAssertEqual(suggestions.first?.providerID, "testset")
    }

    /// A set that doesn't have an app's icon says so by offering nothing, rather
    /// than by offering something wrong.
    func testSuggestionsAreEmptyForAnAppTheSetDoesntCover() async {
        let suggestions = await makeProvider().suggestions(
            appName: "Zap", bundleIdentifier: "ch.lkmc.Zap", limit: 5)
        XCTAssertTrue(suggestions.isEmpty)
    }

    // MARK: Paths

    func testAnIconResolvesInsideTheSetsDirectory() throws {
        let url = try XCTUnwrap(makeProvider().fileURL(forIconName: "firefox"))
        XCTAssertEqual(url.lastPathComponent, "firefox.svg")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path,
                       directory.standardizedFileURL.path)
    }

    /// These names come out of an archive downloaded from the internet, so the
    /// check is the same one stored icons get.
    func testNamesThatCouldEscapeTheDirectoryAreRefused() {
        let provider = makeProvider()
        for name in ["../secret", "/etc/passwd", "sub/dir", "", ".hidden", "a\0b", "a:b"] {
            XCTAssertNil(provider.fileURL(forIconName: name), "\(name) should not resolve")
        }
    }

    /// Themes are full of symlinks. One that points out of the set is not an icon
    /// however it is named, and the resolved path is what says so.
    func testASymlinkPointingOutOfTheSetIsRefused() throws {
        let outside = IconTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("elsewhere.svg")
        try Data("<svg/>".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("escape.svg"), withDestinationURL: target)

        XCTAssertNil(makeProvider().fileURL(forIconName: "escape"))
    }

    // MARK: Fetching

    func testFetchingReadsTheIconFromDisk() async throws {
        let markup = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        try markup.write(to: directory.appendingPathComponent("firefox.svg"))

        let provider = makeProvider()
        let result = try XCTUnwrap(provider.result(forIconName: "firefox"))
        let fetched = await provider.fetchImageData(for: result)
        XCTAssertEqual(fetched.successValue, markup)
    }

    /// The set was searched, then emptied behind Zap's back. Nothing went over a
    /// wire, so the failure must not claim a download went wrong.
    func testFetchingAMissingIconFailsAsUnavailable() async throws {
        let provider = makeProvider()
        let result = try XCTUnwrap(provider.result(forIconName: "firefox"))
        let fetched = await provider.fetchImageData(for: result)
        guard case .failure(.unavailable) = fetched else {
            return XCTFail("expected .unavailable, got \(fetched)")
        }
    }

    /// A result from another provider names nothing here, and must not be resolved
    /// into a path by accident.
    func testFetchingRefusesAResultFromAnotherProvider() async {
        let foreign = IconSearchResult(
            id: "iconify:logos:firefox", title: "firefox", providerID: "iconify",
            imageURL: URL(string: "https://example.invalid/firefox.svg")!,
            isVector: true, credit: nil, creditURL: nil, license: nil)
        let fetched = await makeProvider().fetchImageData(for: foreign)
        XCTAssertNil(fetched.successValue)
    }
}

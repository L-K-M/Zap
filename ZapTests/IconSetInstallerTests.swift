import Foundation
import XCTest
@testable import Zap

/// Downloading a theme and keeping the part Zap needs (`UNJAILED.md §5.6`).
///
/// These build a real `.tar.gz` laid out the way a GitHub source archive is, serve
/// it over a stubbed `URLSession`, and run the installer against it. The selective
/// extraction is the risky part of this feature — a glob and a component count that
/// don't match the archive install an empty set — and only an end-to-end run can
/// tell whether `tar` agrees with what the catalogue claims.
final class IconSetInstallerTests: XCTestCase {

    private var scratch: URL!
    private var destination: URL!

    private func makeSet(glob: String = "*/Papirus/64x64/apps/*.svg",
                         strip: Int = 4) -> IconSet {
        IconSet(id: "testset", name: "Test Set", owner: "example", repository: "theme",
                branch: "main", license: "GPL-3.0", licenseURL: nil, homepage: nil,
                archiveGlob: glob, strippedComponents: strip)
    }

    override func setUp() {
        super.setUp()
        scratch = IconTestSupport.makeTemporaryDirectory()
        destination = scratch.appendingPathComponent("installed", isDirectory: true)
        ArchiveURLProtocol.archive = nil
        ArchiveURLProtocol.statusCode = 200
        ArchiveURLProtocol.etag = nil
        ArchiveURLProtocol.lastIfNoneMatch = nil
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        ArchiveURLProtocol.archive = nil
        scratch = nil
        destination = nil
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ArchiveURLProtocol.self]
        // No cache at all, so a stubbed 304 is delivered as a 304 rather than being
        // resolved against something URLSession stored on an earlier test.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }

    // MARK: Fixture

    /// Builds an archive shaped like `github.com/…/archive/refs/heads/master.tar.gz`:
    /// one root directory carrying the branch name, the theme under it, and plenty
    /// that the glob is supposed to leave behind.
    private func makeArchive(apps: [String] = ["firefox", "slack", "google-chrome"]) throws -> Data {
        let root = scratch.appendingPathComponent("build", isDirectory: true)
        // Cleared first: a test that builds two archives in a row was otherwise
        // getting the union of them, because the second call laid its files down
        // beside the first call's and `tar` took both.
        try? FileManager.default.removeItem(at: root)
        let theme = root.appendingPathComponent("theme-main/Papirus", isDirectory: true)
        let appsDirectory = theme.appendingPathComponent("64x64/apps", isDirectory: true)
        let places = theme.appendingPathComponent("64x64/places", isDirectory: true)
        let bigger = theme.appendingPathComponent("128x128/apps", isDirectory: true)
        for directory in [appsDirectory, places, bigger] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for name in apps {
            try Data("<svg id=\"\(name)\"/>".utf8)
                .write(to: appsDirectory.appendingPathComponent("\(name).svg"))
        }
        // Everything below is what the glob has to leave out — 27 MB of it, upstream.
        try Data("<svg/>".utf8).write(to: places.appendingPathComponent("folder.svg"))
        try Data("<svg/>".utf8).write(to: bigger.appendingPathComponent("firefox.svg"))
        try Data("GPL".utf8).write(to: root.appendingPathComponent("theme-main/LICENSE"))

        let archive = scratch.appendingPathComponent("archive.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path, "-C", root.path, "theme-main"]
        try tar.run()
        tar.waitUntilExit()
        XCTAssertEqual(tar.terminationStatus, 0, "couldn't build the test archive")
        return try Data(contentsOf: archive)
    }

    // MARK: Installing

    func testInstallingKeepsOnlyWhatTheGlobMatches() async throws {
        ArchiveURLProtocol.archive = try makeArchive()

        let outcome = await IconSetInstaller.install(makeSet(), into: destination,
                                                     session: makeSession())
        guard case .success(.installed(let installation)) = outcome else {
            return XCTFail("expected an install, got \(outcome)")
        }
        XCTAssertEqual(installation.iconCount, 3)
        XCTAssertEqual(IconSetInstaller.installedIconNames(in: destination),
                       ["firefox", "slack", "google-chrome"])
    }

    /// `--strip-components` is what flattens the theme's own tree away, so nothing
    /// downstream has to know how the archive was laid out.
    func testIconsLandAsBareFileNames() async throws {
        ArchiveURLProtocol.archive = try makeArchive(apps: ["firefox"])

        _ = await IconSetInstaller.install(makeSet(), into: destination, session: makeSession())
        let file = destination.appendingPathComponent("firefox.svg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    /// A glob that matches nothing means upstream moved its layout. Failing loudly
    /// is the point: the alternative is a set that installs cleanly and is empty.
    ///
    /// `tar` itself refuses a pattern that matches no entry, so this lands as an
    /// extraction failure — `.nothingMatched` is the case below, where `tar` is
    /// perfectly happy and what it extracted still isn't icons.
    func testAGlobThatMatchesNothingFails() async throws {
        ArchiveURLProtocol.archive = try makeArchive()

        let outcome = await IconSetInstaller.install(
            makeSet(glob: "*/Papirus/999x999/apps/*.svg"), into: destination, session: makeSession())
        XCTAssertNotNil(outcome.failureValue)
        XCTAssertTrue(IconSetInstaller.installedIconNames(in: destination).isEmpty)
    }

    /// The set installs cleanly and has nothing in it. Refused, because a set that
    /// is silently empty is worse than one that failed.
    func testExtractingSomethingThatIsntIconsIsRefused() async throws {
        ArchiveURLProtocol.archive = try makeArchive()

        let outcome = await IconSetInstaller.install(
            makeSet(glob: "*/LICENSE", strip: 1), into: destination, session: makeSession())
        XCTAssertEqual(outcome.failureValue, .nothingMatched(glob: "*/LICENSE"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    /// The reason extraction is staged. A failed *update* must not cost the user the
    /// working theme they already had.
    func testAFailedUpdateLeavesTheInstalledSetIntact() async throws {
        ArchiveURLProtocol.archive = try makeArchive()
        _ = await IconSetInstaller.install(makeSet(), into: destination, session: makeSession())

        let outcome = await IconSetInstaller.install(
            makeSet(glob: "*/nowhere/*.svg"), into: destination, session: makeSession())
        XCTAssertNotNil(outcome.failureValue)
        XCTAssertEqual(IconSetInstaller.installedIconNames(in: destination).count, 3)
    }

    func testAReinstallReplacesWhatWasThere() async throws {
        ArchiveURLProtocol.archive = try makeArchive(apps: ["firefox", "slack"])
        _ = await IconSetInstaller.install(makeSet(), into: destination, session: makeSession())

        ArchiveURLProtocol.archive = try makeArchive(apps: ["firefox"])
        _ = await IconSetInstaller.install(makeSet(), into: destination, session: makeSession())
        XCTAssertEqual(IconSetInstaller.installedIconNames(in: destination), ["firefox"])
    }

    // MARK: Updating

    /// The whole reason the record keeps an `ETag`: checking a theme that hasn't
    /// moved should cost a round trip, not 31 MB.
    func testAConditionalRequestIsSentAndA304LeavesDiskAlone() async throws {
        ArchiveURLProtocol.archive = try makeArchive()
        _ = await IconSetInstaller.install(makeSet(), into: destination, session: makeSession())

        ArchiveURLProtocol.statusCode = 304
        let outcome = await IconSetInstaller.install(makeSet(), into: destination,
                                                     ifNoneMatch: "\"abc\"", session: makeSession())
        XCTAssertEqual(outcome.successValue, .unchanged)
        XCTAssertEqual(ArchiveURLProtocol.lastIfNoneMatch, "\"abc\"")
        XCTAssertEqual(IconSetInstaller.installedIconNames(in: destination).count, 3)
    }

    func testTheETagIsRecordedForTheNextCheck() async throws {
        ArchiveURLProtocol.archive = try makeArchive()
        ArchiveURLProtocol.etag = "\"deadbeef\""

        let outcome = await IconSetInstaller.install(makeSet(), into: destination,
                                                     session: makeSession())
        guard case .success(.installed(let installation)) = outcome else {
            return XCTFail("expected an install, got \(outcome)")
        }
        XCTAssertEqual(installation.etag, "\"deadbeef\"")
    }

    // MARK: Failures

    func testAServerErrorIsReportedRatherThanUnpacked() async throws {
        ArchiveURLProtocol.archive = Data("not an archive".utf8)
        ArchiveURLProtocol.statusCode = 500

        let outcome = await IconSetInstaller.install(makeSet(), into: destination,
                                                     session: makeSession())
        XCTAssertNotNil(outcome.failureValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testSomethingThatIsntAnArchiveFails() async {
        ArchiveURLProtocol.archive = Data(repeating: 0x7A, count: 4096)

        let outcome = await IconSetInstaller.install(makeSet(), into: destination,
                                                     session: makeSession())
        XCTAssertNotNil(outcome.failureValue)
    }

    // MARK: Listing

    /// Themes alias by symlink. One that still resolves is a real, differently-named
    /// icon; one left dangling by a selective extraction is not an icon at all.
    func testDanglingSymlinksArentCountedAsIcons() throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("<svg/>".utf8).write(to: destination.appendingPathComponent("firefox.svg"))
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("browser.svg"),
            withDestinationURL: destination.appendingPathComponent("firefox.svg"))
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("ghost.svg"),
            withDestinationURL: destination.appendingPathComponent("never-extracted.svg"))

        XCTAssertEqual(IconSetInstaller.installedIconNames(in: destination),
                       ["firefox", "browser"])
    }
}

/// Serves a canned archive for any request, recording what was asked for.
///
/// Download tasks go through `URLProtocol` like any other, so this is enough to
/// exercise the real `install` path without reaching the network.
final class ArchiveURLProtocol: URLProtocol {

    nonisolated(unsafe) static var archive: Data?
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var etag: String?
    nonisolated(unsafe) static var lastIfNoneMatch: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastIfNoneMatch = request.value(forHTTPHeaderField: "If-None-Match")

        var headers: [String: String] = [:]
        if let etag = Self.etag { headers["ETag"] = etag }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if Self.statusCode != 304, let archive = Self.archive {
            client?.urlProtocol(self, didLoad: archive)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

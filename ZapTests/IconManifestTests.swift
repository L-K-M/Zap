import XCTest
@testable import Zap

final class IconManifestTests: XCTestCase {

    // MARK: Round trip

    func testJSONRoundTrip() throws {
        var manifest = IconManifest()
        manifest.entries["com.apple.Safari"] = IconManifest.Entry(
            file: "com.apple.Safari.png",
            source: IconManifest.Origin.search.rawValue,
            provider: "macosicons",
            credit: "Some Person",
            creditURL: "https://macosicons.com/",
            license: "CC BY 4.0",
            addedAt: Date(timeIntervalSince1970: 1_780_000_000),
            bleed: 0.08,
            trim: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(IconManifest.self, from: encoder.encode(manifest))
        XCTAssertEqual(decoded, manifest)
    }

    func testUnknownFieldsAreIgnored() throws {
        let json = """
        {
          "version": 1,
          "entries": {
            "com.apple.Safari": {
              "file": "com.apple.Safari.png",
              "source": "file",
              "somethingFromTheFuture": {"nested": [1, 2, 3]}
            }
          },
          "alsoFromTheFuture": true
        }
        """.data(using: .utf8)!

        let manifest = try JSONDecoder().decode(IconManifest.self, from: json)
        XCTAssertEqual(manifest.entries["com.apple.Safari"]?.file, "com.apple.Safari.png")
    }

    func testMissingOptionalFieldsDecode() throws {
        let json = #"{"version": 1, "entries": {"a.b": {"file": "a.b.png"}}}"#.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(IconManifest.self, from: json)
        XCTAssertNil(manifest.entries["a.b"]?.credit)
        // An absent `source` reads as a user-chosen file.
        XCTAssertEqual(manifest.entries["a.b"]?.origin, .file)
    }

    // MARK: Validation

    func testUnparseableOriginFallsBackToFile() {
        var manifest = IconManifest()
        manifest.entries["a.b"] = IconManifest.Entry(file: "a.b.png", source: "telepathy")

        let validated = manifest.validated()
        XCTAssertEqual(validated.entries["a.b"]?.origin, .file)
        XCTAssertEqual(validated.entries["a.b"]?.source, IconManifest.Origin.file.rawValue)
    }

    func testBleedIsClamped() {
        var manifest = IconManifest()
        manifest.entries["high"] = IconManifest.Entry(file: "high.png", bleed: 9)
        manifest.entries["low"] = IconManifest.Entry(file: "low.png", bleed: -4)
        manifest.entries["nan"] = IconManifest.Entry(file: "nan.png", bleed: .nan)

        let validated = manifest.validated()
        XCTAssertEqual(validated.entries["high"]?.bleed, IconManifest.maximumBleed)
        XCTAssertEqual(validated.entries["low"]?.bleed, 0)
        XCTAssertNil(validated.entries["nan"]?.bleed)
    }

    func testSystemPinNeedsNoFileAndKeepsNone() {
        var manifest = IconManifest()
        manifest.entries["a.b"] = IconManifest.Entry(
            file: "somebody-elses.png", source: IconManifest.Origin.system.rawValue)

        let validated = manifest.validated()
        XCTAssertEqual(validated.entries["a.b"]?.origin, .system)
        XCTAssertNil(validated.entries["a.b"]?.file)
    }

    func testEntryWithoutAFileIsDropped() {
        var manifest = IconManifest()
        manifest.entries["a.b"] = IconManifest.Entry(source: IconManifest.Origin.file.rawValue)
        XCTAssertTrue(manifest.validated().entries.isEmpty)
    }

    func testValidationNormalisesTheVersion() {
        var manifest = IconManifest(version: 99)
        manifest.entries["a.b"] = IconManifest.Entry(file: "a.b.png")
        XCTAssertEqual(manifest.validated().version, IconManifest.currentVersion)
        // A manifest from a future version still yields its usable entries.
        XCTAssertEqual(manifest.validated().entries.count, 1)
    }

    // MARK: Path traversal

    func testUnsafeFileNamesAreRejected() {
        let unsafe = [
            "../evil.png",
            "../../../../etc/passwd.png",
            "/etc/passwd.png",
            "subdir/icon.png",
            "back\\slash.png",
            "",
            ".hidden.png",
            "icon.png.exe",
            "icon.icns",              // Zap only ever writes PNGs here
            "..png",                  // a relative component wearing an extension
        ]
        for name in unsafe {
            XCTAssertFalse(IconManifest.isSafeFileName(name), "should reject \(name)")
        }
    }

    func testSafeFileNamesAreAccepted() {
        for name in ["com.apple.Safari.png", "a.png", "com.googlecode.iterm2.png", "A-B_C.PNG"] {
            XCTAssertTrue(IconManifest.isSafeFileName(name), "should accept \(name)")
        }
    }

    func testEntriesWithTraversingFileNamesAreDropped() {
        var manifest = IconManifest()
        manifest.entries["escape"] = IconManifest.Entry(file: "../../evil.png")
        manifest.entries["absolute"] = IconManifest.Entry(file: "/etc/passwd.png")
        manifest.entries["fine"] = IconManifest.Entry(file: "fine.png")

        let validated = manifest.validated()
        XCTAssertEqual(Set(validated.entries.keys), ["fine"])
    }

    func testResolvedURLStaysInsideTheDirectory() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let resolved = try XCTUnwrap(IconManifest.resolvedURL(forFile: "a.b.png", in: directory))
        XCTAssertEqual(resolved.lastPathComponent, "a.b.png")
        XCTAssertNil(IconManifest.resolvedURL(forFile: "../a.b.png", in: directory))
        XCTAssertNil(IconManifest.resolvedURL(forFile: "/tmp/a.b.png", in: directory))
    }

    // MARK: Generated file names

    func testGeneratedFileNamesAreAlwaysSafe() {
        let hostile = [
            "com.apple.Safari",
            "../../../etc/passwd",
            "..",
            ".",
            "",
            "with spaces and /slashes/",
            String(repeating: "x", count: 500),
            "emoji-🙂-id",
        ]
        for bundleID in hostile {
            let name = IconManifest.fileName(forBundleID: bundleID)
            XCTAssertTrue(IconManifest.isSafeFileName(name),
                          "generated an unsafe name \(name) for \(bundleID)")
        }
    }

    func testGeneratedFileNameKeepsAWellFormedBundleID() {
        XCTAssertEqual(IconManifest.fileName(forBundleID: "com.apple.Safari"), "com.apple.Safari.png")
    }

    func testGeneratedFileNamesDontCollideAfterSanitising() {
        // Both sanitise to the same stem; the digest is what keeps them apart.
        let first = IconManifest.fileName(forBundleID: "a/b")
        let second = IconManifest.fileName(forBundleID: "a:b")
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(IconManifest.isSafeFileName(first))
        XCTAssertTrue(IconManifest.isSafeFileName(second))
    }

    func testGeneratedFileNamesAreStableAcrossCalls() {
        // Persisted in the manifest, so it must not move between launches — which
        // rules out `hashValue`.
        XCTAssertEqual(IconManifest.shortDigest(of: "com.apple.Safari"),
                       IconManifest.shortDigest(of: "com.apple.Safari"))
        XCTAssertNotEqual(IconManifest.shortDigest(of: "com.apple.Safari"),
                          IconManifest.shortDigest(of: "com.apple.Mail"))
    }
}

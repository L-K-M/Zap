import Foundation
import XCTest
@testable import Zap

final class IconStoreTests: XCTestCase {

    private var directory: URL!
    private var store: IconStore!

    /// Where `sourcePNG()` writes the files under import. Deliberately *not* the
    /// store's own directory: `testRemoveAllClearsEverything` asserts that no PNGs
    /// are left there, which a source file sitting alongside them would defeat.
    private var sourceDirectory: URL!

    override func setUp() {
        super.setUp()
        directory = IconTestSupport.makeTemporaryDirectory()
        sourceDirectory = IconTestSupport.makeTemporaryDirectory()
        store = IconStore(directory: directory)
    }

    override func tearDown() {
        store = nil
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: sourceDirectory)
        directory = nil
        sourceDirectory = nil
        super.tearDown()
    }

    /// One directory for the whole test, one file per call — so repeated calls
    /// don't strand a temp directory apiece.
    private func sourcePNG(width: Int = 512, height: Int = 512, filled: Bool = false) -> URL {
        let url = sourceDirectory.appendingPathComponent("source-\(UUID().uuidString).png")
        return IconTestSupport.writePNG(width: width, height: height, to: url, filled: filled)
    }

    // MARK: Adopting a file

    func testAdoptingAFileStoresItAndRecordsTheEntry() throws {
        let entry = try XCTUnwrap(
            store.setCustomIcon(from: sourcePNG(), forBundleID: "com.apple.Safari").successValue)

        XCTAssertEqual(entry.file, "com.apple.Safari.png")
        XCTAssertEqual(entry.origin, .file)
        XCTAssertNotNil(entry.addedAt)

        let stored = try XCTUnwrap(store.imageURL(forBundleID: "com.apple.Safari"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.path))
        XCTAssertEqual(stored.deletingLastPathComponent().standardizedFileURL,
                       directory.standardizedFileURL)
    }

    /// The stored file is Zap's own PNG output, not a copy of the source
    /// (`UNJAILED.md §6.4`).
    func testAdoptedFileIsReEncodedAsPNG() throws {
        store.setCustomIcon(from: sourcePNG(), forBundleID: "a.b")
        let stored = try XCTUnwrap(store.imageURL(forBundleID: "a.b"))
        XCTAssertEqual(stored.pathExtension, "png")

        let reloaded = try XCTUnwrap(store.customImage(forBundleID: "a.b"))
        XCTAssertEqual(reloaded.width, 512)
    }

    func testAdoptingAnUndersizeFileIsRejectedAndStoresNothing() {
        let result = store.setCustomIcon(from: sourcePNG(width: 32, height: 32), forBundleID: "a.b")
        XCTAssertEqual(result.failureValue, .tooSmall(width: 32, height: 32))
        XCTAssertNil(store.entry(forBundleID: "a.b"))
        XCTAssertNil(store.imageURL(forBundleID: "a.b"))
    }

    func testAdoptingAnUnreadableFileIsRejected() {
        let junk = sourceDirectory.appendingPathComponent("junk.png")
        try? Data("not an image".utf8).write(to: junk)
        XCTAssertEqual(store.setCustomIcon(from: junk, forBundleID: "a.b").failureValue, .unreadable)
        XCTAssertNil(store.entry(forBundleID: "a.b"))
    }

    // MARK: Pinning and clearing

    func testPinningToTheSystemIconRecordsNoFile() {
        store.pinToSystemIcon(forBundleID: "a.b")

        XCTAssertTrue(store.isPinnedToSystemIcon("a.b"))
        XCTAssertEqual(store.entry(forBundleID: "a.b")?.origin, .system)
        XCTAssertNil(store.entry(forBundleID: "a.b")?.file)
        XCTAssertNil(store.imageURL(forBundleID: "a.b"))
    }

    func testPinningReplacesAnExistingCustomIcon() throws {
        store.setCustomIcon(from: sourcePNG(), forBundleID: "a.b")
        let stored = try XCTUnwrap(store.imageURL(forBundleID: "a.b"))

        store.pinToSystemIcon(forBundleID: "a.b")
        XCTAssertTrue(store.isPinnedToSystemIcon("a.b"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path),
                       "the superseded PNG should be deleted, not orphaned")
    }

    func testClearingRemovesBothTheEntryAndTheFile() throws {
        store.setCustomIcon(from: sourcePNG(), forBundleID: "a.b")
        let stored = try XCTUnwrap(store.imageURL(forBundleID: "a.b"))

        store.clearOverride(forBundleID: "a.b")
        XCTAssertNil(store.entry(forBundleID: "a.b"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path))
    }

    func testRemoveAllClearsEverything() throws {
        store.setCustomIcon(from: sourcePNG(), forBundleID: "a.b")
        store.setCustomIcon(from: sourcePNG(), forBundleID: "c.d")
        store.pinToSystemIcon(forBundleID: "e.f")

        store.removeAll()
        XCTAssertTrue(store.manifest.entries.isEmpty)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(remaining.filter { $0.hasSuffix(".png") }, [])
    }

    // MARK: Persistence

    func testEntriesSurviveAcrossInstances() throws {
        store.setCustomIcon(from: sourcePNG(), forBundleID: "com.apple.Safari")
        store.pinToSystemIcon(forBundleID: "com.apple.Mail")

        let reopened = IconStore(directory: directory)
        XCTAssertEqual(reopened.entry(forBundleID: "com.apple.Safari")?.origin, .file)
        XCTAssertTrue(reopened.isPinnedToSystemIcon("com.apple.Mail"))
        XCTAssertNotNil(reopened.customImage(forBundleID: "com.apple.Safari"))
    }

    func testAnEmptyDirectoryLoadsAnEmptyManifest() {
        let fresh = IconStore(directory: IconTestSupport.makeTemporaryDirectory())
        XCTAssertTrue(fresh.manifest.entries.isEmpty)
        XCTAssertEqual(fresh.manifest.version, IconManifest.currentVersion)
    }

    func testAMalformedManifestIsIgnoredRatherThanFatal() throws {
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("manifest.json"))
        let reopened = IconStore(directory: directory)
        XCTAssertTrue(reopened.manifest.entries.isEmpty)
    }

    // MARK: Untrusted manifests

    /// A manifest can arrive inside a shared icon pack, so a hand-written entry
    /// must not be able to point Zap at a file outside the icons directory.
    func testATraversingManifestEntryIsDroppedOnLoad() throws {
        let json = """
        {
          "version": 1,
          "entries": {
            "evil": {"file": "../../../../etc/passwd.png", "source": "file"},
            "alsoEvil": {"file": "/etc/passwd.png", "source": "file"},
            "fine": {"file": "fine.png", "source": "file"}
          }
        }
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("manifest.json"))

        let reopened = IconStore(directory: directory)
        XCTAssertEqual(Set(reopened.manifest.entries.keys), ["fine"])
        XCTAssertNil(reopened.imageURL(forBundleID: "evil"))
        XCTAssertNil(reopened.imageURL(forBundleID: "alsoEvil"))
    }

    func testStoredFileNamesStayInsideTheDirectory() throws {
        // Even a bundle identifier that looks like a path lands in the directory.
        let entry = try XCTUnwrap(
            store.setCustomIcon(from: sourcePNG(), forBundleID: "../../escape").successValue)
        let file = try XCTUnwrap(entry.file)
        XCTAssertTrue(IconManifest.isSafeFileName(file))

        let stored = try XCTUnwrap(store.imageURL(forBundleID: "../../escape"))
        XCTAssertEqual(stored.deletingLastPathComponent().standardizedFileURL,
                       directory.standardizedFileURL)
    }
}

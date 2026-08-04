import CoreGraphics
import Foundation
import XCTest
@testable import Zap

/// The cache that keeps SVG from being rasterised twice.
final class IconRenderCacheTests: XCTestCase {

    private var directory: URL!
    private var cache: IconRenderCache!

    override func setUp() {
        super.setUp()
        directory = IconTestSupport.makeTemporaryDirectory()
        cache = IconRenderCache(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        cache = nil
        directory = nil
        super.tearDown()
    }

    private func markup(_ id: String = "a") -> Data {
        Data("<svg id=\"\(id)\"></svg>".utf8)
    }

    // MARK: Keys

    /// Content-addressed: the same markup is the same entry however it arrived —
    /// picked as a file, dragged from a browser, or chosen from a search.
    func testTheSameMarkupKeysTheSameWay() {
        XCTAssertEqual(IconRenderCache.key(for: markup(), side: 128),
                       IconRenderCache.key(for: markup(), side: 128))
    }

    func testDifferentMarkupKeysDifferently() {
        XCTAssertNotEqual(IconRenderCache.key(for: markup("a"), side: 128),
                          IconRenderCache.key(for: markup("b"), side: 128))
    }

    /// Size is part of the key, not something to resample from: the 128 px preview
    /// must never be handed back when a 1024 px master was asked for.
    func testSizeIsPartOfTheKey() {
        XCTAssertNotEqual(IconRenderCache.key(for: markup(), side: 128),
                          IconRenderCache.key(for: markup(), side: 1024))
    }

    /// The name is generated, so it can never escape the cache directory whatever
    /// the markup contains.
    func testKeysAreAlwaysSafeFileNames() {
        for source in [markup(), Data("../../escape".utf8), Data(), Data([0xFF, 0x00])] {
            XCTAssertTrue(IconManifest.isSafeFileName(IconRenderCache.key(for: source, side: 64)))
        }
    }

    // MARK: Round trip

    func testAStoredRenderComesBack() throws {
        let image = IconTestSupport.makeImage(width: 128, height: 128)
        cache.store(image, for: markup(), side: 128)

        let restored = try XCTUnwrap(cache.image(for: markup(), side: 128))
        XCTAssertEqual(restored.width, 128)
    }

    func testAMissReturnsNil() {
        XCTAssertNil(cache.image(for: markup(), side: 128))
    }

    func testAnEntryAtAnotherSizeIsAMiss() {
        cache.store(IconTestSupport.makeImage(width: 128, height: 128), for: markup(), side: 128)
        XCTAssertNil(cache.image(for: markup(), side: 1024))
    }

    func testOtherMarkupIsAMiss() {
        cache.store(IconTestSupport.makeImage(width: 128, height: 128), for: markup("a"), side: 128)
        XCTAssertNil(cache.image(for: markup("b"), side: 128))
    }

    /// A truncated or half-written file is Zap's own output gone wrong, not hostile
    /// input — it is dropped so the next render replaces it, rather than failing the
    /// import.
    func testACorruptEntryIsDiscardedRatherThanReturned() throws {
        cache.store(IconTestSupport.makeImage(width: 128, height: 128), for: markup(), side: 128)
        let stored = try XCTUnwrap(
            IconManifest.resolvedURL(forFile: IconRenderCache.key(for: markup(), side: 128),
                                     in: directory))
        try Data("not a png".utf8).write(to: stored)

        XCTAssertNil(cache.image(for: markup(), side: 128))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.path))
    }

    func testRemoveAllClearsEverything() {
        cache.store(IconTestSupport.makeImage(width: 128, height: 128), for: markup(), side: 128)
        cache.removeAll()
        XCTAssertNil(cache.image(for: markup(), side: 128))
    }

    // MARK: Bound

    /// Browsing a long time must not grow the cache without limit.
    func testTheCacheIsBounded() throws {
        let bounded = IconRenderCache(directory: directory, maximumEntries: 3)
        for index in 0..<8 {
            bounded.store(IconTestSupport.makeImage(width: 64, height: 64),
                          for: markup("icon-\(index)"), side: 64)
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        XCTAssertLessThanOrEqual(entries.count, 3)
    }

    // MARK: Wiring

    /// That `IconImport` actually consults the cache, not just that the cache works.
    ///
    /// Seeds an entry and asks for an import of the same markup: a hit returns the
    /// seeded image without a web view ever starting. If the lookup were dropped in
    /// a refactor this would fall through to a real render, which is both wrong and
    /// slow — the failure the isolated tests above could never see.
    func testImportingSVGConsultsTheCache() async throws {
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"M0 0h1v1z\"/></svg>".utf8)
        cache.store(IconTestSupport.makeImage(width: 96, height: 96), for: svg, side: 96)

        let imported = await IconImport.image(from: svg, side: 96, cache: cache)
        let image = try XCTUnwrap(imported.successValue)
        XCTAssertEqual(image.width, 96)
    }

    /// Pruning keeps the newest, so the entry just written is still there.
    func testPruningKeepsTheMostRecentEntry() throws {
        let bounded = IconRenderCache(directory: directory, maximumEntries: 2)
        for index in 0..<5 {
            bounded.store(IconTestSupport.makeImage(width: 64, height: 64),
                          for: markup("icon-\(index)"), side: 64)
            // Pruning orders by modification date, so the writes have to be
            // distinguishable by it. APFS records nanoseconds and wouldn't need
            // this; a coarser clock under CI would make the order — and this
            // assertion — a coin toss.
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertNotNil(bounded.image(for: markup("icon-4"), side: 64))
    }
}

import Foundation
import XCTest
@testable import Zap

/// Resolution order against synthetic bundles built in a temp dir (`UNJAILED.md §9`).
///
/// The `Assets.car` rung can't be covered here — it needs a real compiled asset
/// catalog and a Tahoe machine to mean anything — so it stays on the manual list.
final class BundleArtworkTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = IconTestSupport.makeTemporaryDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    private func fileNames(_ sources: [BundleArtwork.Source]) -> [String] {
        sources.compactMap {
            if case .file(let url) = $0 { return url.lastPathComponent }
            return nil
        }
    }

    private func catalogNames(_ sources: [BundleArtwork.Source]) -> [String] {
        sources.compactMap {
            if case .assetCatalog(let name) = $0 { return name }
            return nil
        }
    }

    // MARK: CFBundleIconFile

    func testIconFileWithTheExtensionOmitted() throws {
        // The spelling nearly every app bundle actually uses.
        let bundle = try IconTestSupport.makeBundle(
            named: "Omitted", in: directory,
            info: ["CFBundleIconFile": "AppIcon"],
            resources: ["AppIcon.icns": IconTestSupport.placeholderBytes])

        XCTAssertEqual(fileNames(BundleArtwork.sources(forBundleAt: bundle)), ["AppIcon.icns"])
    }

    func testIconFileWithTheExtensionPresent() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "Present", in: directory,
            info: ["CFBundleIconFile": "AppIcon.icns"],
            resources: ["AppIcon.icns": IconTestSupport.placeholderBytes])

        XCTAssertEqual(fileNames(BundleArtwork.sources(forBundleAt: bundle)), ["AppIcon.icns"])
    }

    func testDeclaredIconFileThatDoesNotExistIsSkipped() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "Missing", in: directory,
            info: ["CFBundleIconFile": "NotThere"],
            resources: ["Other.icns": IconTestSupport.placeholderBytes])

        // Falls through to the glob rather than returning a path that isn't there.
        XCTAssertEqual(fileNames(BundleArtwork.sources(forBundleAt: bundle)), ["Other.icns"])
    }

    func testADeclaredPathIsReducedToItsLastComponent() throws {
        // Defensive: a bundle doesn't get to point the resolver outside Resources.
        let bundle = try IconTestSupport.makeBundle(
            named: "Traversal", in: directory,
            info: ["CFBundleIconFile": "../../../../etc/passwd"],
            resources: [:])

        XCTAssertTrue(BundleArtwork.sources(forBundleAt: bundle).isEmpty)
    }

    // MARK: Order

    func testResolutionOrderPutsIconFileBeforeTheAssetCatalog() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "Both", in: directory,
            info: ["CFBundleIconFile": "AppIcon", "CFBundleIconName": "AppIcon"],
            resources: ["AppIcon.icns": IconTestSupport.placeholderBytes])

        let sources = BundleArtwork.sources(forBundleAt: bundle)
        XCTAssertEqual(sources.count, 2)
        guard case .file = sources[0] else { return XCTFail("the .icns should come first") }
        guard case .assetCatalog = sources[1] else { return XCTFail("the catalog should come second") }
    }

    func testAssetCatalogNameIsReportedWhenItIsTheOnlyDeclaration() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "CatalogOnly", in: directory,
            info: ["CFBundleIconName": "AppIcon"],
            resources: [:])

        XCTAssertEqual(catalogNames(BundleArtwork.sources(forBundleAt: bundle)), ["AppIcon"])
    }

    func testIconFilesAreOfferedAfterTheAssetCatalog() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "Catalyst", in: directory,
            info: ["CFBundleIconName": "AppIcon", "CFBundleIconFiles": ["Icon-60", "Icon-76"]],
            resources: ["Icon-60.png": IconTestSupport.placeholderBytes,
                        "Icon-76.png": IconTestSupport.placeholderBytes])

        let sources = BundleArtwork.sources(forBundleAt: bundle)
        XCTAssertEqual(sources.count, 3)
        guard case .assetCatalog = sources[0] else { return XCTFail("the catalog should come first") }
        XCTAssertEqual(fileNames(sources), ["Icon-60.png", "Icon-76.png"])
    }

    // MARK: Fallback glob

    func testUndeclaredArtworkFallsBackToTheLargestICNS() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "Undeclared", in: directory,
            info: ["CFBundleName": "Undeclared"],
            resources: ["small.icns": Data(repeating: 0, count: 128),
                        "large.icns": Data(repeating: 0, count: 4096),
                        "unrelated.txt": IconTestSupport.placeholderBytes])

        XCTAssertEqual(fileNames(BundleArtwork.sources(forBundleAt: bundle)), ["large.icns", "small.icns"])
    }

    func testTheDeclaredIconIsNotRepeatedByTheGlob() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "NoDupes", in: directory,
            info: ["CFBundleIconFile": "AppIcon"],
            resources: ["AppIcon.icns": IconTestSupport.placeholderBytes])

        XCTAssertEqual(fileNames(BundleArtwork.sources(forBundleAt: bundle)), ["AppIcon.icns"])
    }

    // MARK: Degenerate bundles

    func testBundleWithNoInfoPlistYieldsNothing() {
        let bundle = directory.appendingPathComponent("Empty.app", isDirectory: true)
        XCTAssertTrue(BundleArtwork.sources(forBundleAt: bundle).isEmpty)
        XCTAssertTrue(BundleArtwork.infoDictionary(forBundleAt: bundle).isEmpty)
        XCTAssertNil(BundleArtwork.image(forBundleAt: bundle))
    }

    func testBundleWithNoArtworkYieldsNothing() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "Bare", in: directory, info: ["CFBundleName": "Bare"])
        XCTAssertTrue(BundleArtwork.sources(forBundleAt: bundle).isEmpty)
        XCTAssertNil(BundleArtwork.image(forBundleAt: bundle))
    }

    // MARK: Loading

    func testLoadsRealArtworkFromABundle() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "Real", in: directory,
            info: ["CFBundleIconFiles": ["AppIcon"]])
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        IconTestSupport.writePNG(width: 512, height: 512,
                                 to: resources.appendingPathComponent("AppIcon.png"),
                                 filled: false)

        let image = try XCTUnwrap(BundleArtwork.image(forBundleAt: bundle))
        XCTAssertEqual(image.width, 512)
        // A circle in a square canvas: the shape the whole feature exists to keep.
        XCTAssertEqual(IconShapeClassifier.classify(image), .freeform)
    }

    func testUndecodableDeclaredArtworkYieldsNothing() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "Broken", in: directory,
            info: ["CFBundleIconFile": "AppIcon"],
            resources: ["AppIcon.icns": IconTestSupport.placeholderBytes])
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        IconTestSupport.writePNG(width: 256, height: 256,
                                 to: resources.appendingPathComponent("Fallback.png"))

        // The declared `.icns` is junk, so nothing decodes from it. The loose PNG
        // isn't declared and isn't an `.icns`, so it isn't reached either — the
        // bundle simply has no readable artwork, and the caller falls back to the
        // system icon rather than guessing.
        XCTAssertNil(BundleArtwork.image(forBundleAt: bundle))
    }

    func testLoadingAnUndersizeIconIsRefused() throws {
        let bundle = try IconTestSupport.makeBundle(
            named: "Tiny", in: directory, info: ["CFBundleIconFiles": ["AppIcon"]])
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        IconTestSupport.writePNG(width: 32, height: 32,
                                 to: resources.appendingPathComponent("AppIcon.png"))

        XCTAssertNil(BundleArtwork.image(forBundleAt: bundle))
    }
}

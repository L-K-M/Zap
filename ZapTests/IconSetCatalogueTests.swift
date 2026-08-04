import Foundation
import XCTest
@testable import Zap

/// The catalogue rows and the library that installs them (`UNJAILED.md §5.6`).
///
/// A row is data, and getting it wrong is the way this feature fails quietly: a
/// glob that doesn't match the archive installs nothing, and a component count that
/// doesn't match the glob buries the icons under directories no one looks in. Both
/// are checkable without downloading anything.
final class IconSetCatalogueTests: XCTestCase {

    // MARK: Rows

    func testEveryEntryHasAnArchiveURLOnItsOwnRepository() throws {
        for set in IconSetCatalogue.all {
            let url = try XCTUnwrap(set.archiveURL, "\(set.id) has no archive URL")
            XCTAssertEqual(url.host, "github.com")
            XCTAssertTrue(url.path.hasPrefix("/\(set.owner)/\(set.repository)/"))
            XCTAssertTrue(url.path.hasSuffix("/\(set.branch).tar.gz"))
        }
    }

    /// §5.4 makes attribution the condition for a source existing at all, and the
    /// credit is carried on every result the set produces.
    func testEveryEntryStatesALicence() {
        for set in IconSetCatalogue.all {
            XCTAssertFalse(set.license.isEmpty, "\(set.id) has no licence")
            XCTAssertNotNil(set.homepage, "\(set.id) has no homepage to credit")
            XCTAssertTrue(set.attribution.contains(set.license))
        }
    }

    /// The invariant `IconSet.strippedComponents` documents: the count is the glob's
    /// components up to but excluding the file itself. Off by one and the icons land
    /// nested, or `tar` writes above the destination.
    func testStrippedComponentsMatchesEachGlob() {
        for set in IconSetCatalogue.all {
            let components = set.archiveGlob.split(separator: "/").count
            XCTAssertEqual(set.strippedComponents, components - 1,
                           "\(set.id): \(set.archiveGlob) has \(components) components")
        }
    }

    /// The leading `*` stands for the archive's own root directory, which carries
    /// the branch name and so can't be written out. A glob without it matches
    /// nothing in a GitHub source archive.
    func testEveryGlobAllowsForTheArchiveRoot() {
        for set in IconSetCatalogue.all {
            XCTAssertTrue(set.archiveGlob.hasPrefix("*/"), "\(set.id): \(set.archiveGlob)")
            XCTAssertTrue(set.archiveGlob.hasSuffix(".svg"), "\(set.id): \(set.archiveGlob)")
        }
    }

    func testIdentifiersAreUniqueAndCanNameADirectory() {
        var seen = Set<String>()
        for set in IconSetCatalogue.all {
            XCTAssertTrue(seen.insert(set.id).inserted, "duplicate id \(set.id)")
            XCTAssertTrue(IconSetLibrary.isSafeSetID(set.id), "\(set.id) can't name a directory")
        }
    }

    func testLookupFindsEveryRowAndNothingElse() {
        for set in IconSetCatalogue.all {
            XCTAssertEqual(IconSetCatalogue.set(withID: set.id), set)
        }
        XCTAssertNil(IconSetCatalogue.set(withID: "not-a-set"))
    }

    /// §5.6 is explicit that this is several sets rather than one, and the shipped
    /// list has to actually be several.
    func testMoreThanOneSetIsOffered() {
        XCTAssertGreaterThan(IconSetCatalogue.all.count, 1)
    }

    // MARK: Directory naming

    func testUnsafeSetIdentifiersAreRefused() {
        for id in ["", "../escape", "Papirus", "papirus/dark", "a.b", String(repeating: "a", count: 65)] {
            XCTAssertFalse(IconSetLibrary.isSafeSetID(id), "\(id) should be refused")
        }
    }

    func testALibraryDirectoryIsPerSetAndInsideTheLibrary() throws {
        let root = IconTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = IconSetLibrary(directory: root)

        let papirus = try XCTUnwrap(library.directory(forSetID: "papirus"))
        XCTAssertEqual(papirus.lastPathComponent, "papirus")
        XCTAssertEqual(papirus.deletingLastPathComponent().standardizedFileURL.path,
                       root.standardizedFileURL.path)
        XCTAssertNil(library.directory(forSetID: "../elsewhere"))
    }

    // MARK: Library state

    func testAnEmptyLibraryOffersNoProviders() {
        let root = IconTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = IconSetLibrary(directory: root)

        XCTAssertTrue(library.installedProviders().isEmpty)
        XCTAssertFalse(library.isInstalled(IconSetCatalogue.papirus))
    }

    /// A record naming a set the catalogue no longer carries is dropped on load:
    /// nothing can search it, so keeping it would only be a row claiming a theme is
    /// installed with nothing to do about it.
    func testRecordsForUnknownSetsAreDroppedOnLoad() throws {
        let root = IconTestSupport.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let json = """
        {"retired-set":{"id":"retired-set","installedAt":0,"iconCount":12},\
        "papirus":{"id":"papirus","installedAt":0,"iconCount":34}}
        """
        try Data(json.utf8).write(to: root.appendingPathComponent("sets.json"))

        let library = IconSetLibrary(directory: root)
        XCTAssertEqual(Set(library.records.keys), ["papirus"])
    }
}

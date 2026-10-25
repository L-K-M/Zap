import CoreGraphics
import PictKit
import XCTest
@testable import Zap

/// Tests `SharedIconChange`, the immutable pending write behind the per-app
/// icon confirmation: preparing a change must perform no store I/O, and
/// applying it must affect only its own target. Uses an isolated store in a
/// temporary directory — nothing touches the real shared store.
final class SharedIconChangeTests: XCTestCase {

    private var directory: URL!
    private var store: IconStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zap-icon-tests-\(UUID().uuidString)", isDirectory: true)
        store = IconStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
        super.tearDown()
    }

    private func makeImage() -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 64, height: 64,
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return context.makeImage()!
    }

    private func app(_ id: String) -> AppInfo {
        AppInfo(bundleIdentifier: id,
                name: id,
                processIdentifier: 1,
                bundleURL: URL(fileURLWithPath: "/Applications/\(id).app"))
    }

    /// The stored PNG bytes for `app`'s target, or `nil` when no image file is
    /// stored for it — the raw on-disk bytes, not decoded pixels.
    private func imageData(for app: AppInfo) throws -> Data? {
        guard let url = store.imageURL(for: app.iconTarget) else { return nil }
        return try Data(contentsOf: url)
    }

    private func seedTwoApps() throws -> (AppInfo, AppInfo) {
        let first = app("com.example.first")
        let second = app("com.example.second")
        _ = try store.setIcon(makeImage(), for: first.iconTarget).get()
        _ = try store.setIcon(makeImage(), for: second.iconTarget).get()
        return (first, second)
    }

    /// Choosing a menu item only *prepares* the change — until the destructive
    /// button runs `apply`, entries and stored image bytes must be untouched.
    func testPreparingAndDiscardingAChangePerformsNoIO() throws {
        let (first, second) = try seedTwoApps()
        let entriesBefore = store.entries
        let firstImageBefore = try XCTUnwrap(imageData(for: first))
        let secondImageBefore = try XCTUnwrap(imageData(for: second))

        // The user cancels; neither destination's command is ever applied.
        _ = SharedIconChange(app: first, destination: .originalArtwork)
        _ = SharedIconChange(app: first, destination: .systemIcon)

        XCTAssertEqual(store.entries, entriesBefore)
        XCTAssertEqual(try imageData(for: first), firstImageBefore)
        XCTAssertEqual(try imageData(for: second), secondImageBefore)
    }

    func testApplyingOriginalClearsOnlyItsTarget() throws {
        let (first, second) = try seedTwoApps()
        _ = try XCTUnwrap(imageData(for: first))
        let secondEntryBefore = store.entry(for: second.iconTarget)
        let secondImageBefore = try XCTUnwrap(imageData(for: second))

        SharedIconChange(app: first, destination: .originalArtwork).apply(to: store)

        XCTAssertNil(store.entry(for: first.iconTarget))
        XCTAssertNil(try imageData(for: first))
        XCTAssertEqual(store.entry(for: second.iconTarget), secondEntryBefore)
        XCTAssertEqual(try imageData(for: second), secondImageBefore)
    }

    func testApplyingSystemPinsOnlyItsTarget() throws {
        let (first, second) = try seedTwoApps()
        _ = try XCTUnwrap(imageData(for: first))
        let secondEntryBefore = store.entry(for: second.iconTarget)
        let secondImageBefore = try XCTUnwrap(imageData(for: second))

        SharedIconChange(app: first, destination: .systemIcon).apply(to: store)

        XCTAssertTrue(store.isPinnedToSystemIcon(first.iconTarget))
        XCTAssertEqual(store.entry(for: second.iconTarget), secondEntryBefore)
        XCTAssertEqual(try imageData(for: second), secondImageBefore)
    }

    func testActionTitlesDiscloseEverywhere() {
        let first = app("com.example.first")
        XCTAssertEqual(SharedIconChange(app: first, destination: .originalArtwork).actionTitle,
                       "Use Original Artwork Everywhere")
        XCTAssertEqual(SharedIconChange(app: first, destination: .systemIcon).actionTitle,
                       "Use System Icon Everywhere")
    }
}

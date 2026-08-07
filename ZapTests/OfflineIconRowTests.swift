import Foundation
import PictKit
import XCTest
@testable import Zap

/// Which stored entries get a row of their own in the Icons tab.
///
/// The rule has to see past the key change: an icon set before overrides were
/// keyed by path is still filed under the bundle identifier, and treating that as
/// a different app puts a second row on screen for one already in the list.
///
/// Rewritten for the shared store — the old version keyed on manifest strings;
/// this one keys on `IconEntryKey`, which is what the store hands back.
final class OfflineIconRowTests: XCTestCase {

    private func app(_ bundleID: String, at path: String? = nil) -> AppInfo {
        AppInfo(bundleIdentifier: bundleID, name: bundleID, processIdentifier: 1,
                bundleURL: path.map { URL(fileURLWithPath: $0) })
    }

    private let safariByID = IconEntryKey.app(bundleIdentifier: "com.apple.Safari")
    private let safariByPath = IconEntryKey.app(
        at: URL(fileURLWithPath: "/Applications/Safari.app"))

    // MARK: The upgrade path

    /// The regression this exists for. Safari is running and its icon was set
    /// before the key change, so the store still says `com.apple.Safari` — which
    /// must not read as an absent app.
    func testALegacyEntryForARunningAppGetsNoSecondRow() {
        let rows = IconsView.offlineRows(
            storeKeys: [safariByID],
            running: [app("com.apple.Safari", at: "/Applications/Safari.app")])
        XCTAssertTrue(rows.isEmpty)
    }

    /// The same app once it has been re-saved under the new key.
    func testAPathEntryForARunningAppGetsNoSecondRow() {
        let rows = IconsView.offlineRows(
            storeKeys: [safariByPath],
            running: [app("com.apple.Safari", at: "/Applications/Safari.app")])
        XCTAssertTrue(rows.isEmpty)
    }

    /// And mid-upgrade, with both present, it is still one app.
    func testBothKeysForOneRunningAppGetNoRows() {
        let rows = IconsView.offlineRows(
            storeKeys: [safariByID, safariByPath],
            running: [app("com.apple.Safari", at: "/Applications/Safari.app")])
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: Still listing what it should

    /// The reason the offline list exists: an app that isn't running would
    /// otherwise be unreachable, and the user could never undo its icon.
    func testAnAbsentAppStillGetsARow() {
        let rows = IconsView.offlineRows(storeKeys: [safariByPath], running: [])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "Safari")
    }

    func testAnAbsentAppKnownOnlyByIdentifierStillGetsARow() {
        let rows = IconsView.offlineRows(storeKeys: [safariByID], running: [])
        XCTAssertEqual(rows.count, 1)
        // Pin which row, not just how many: a fallback that synthesised a
        // placeholder would otherwise satisfy the count and nothing else.
        XCTAssertEqual(rows.first?.bundleIdentifier, "com.apple.Safari")
    }

    /// A different app being on screen doesn't cover for one that isn't.
    func testARunningAppDoesNotCoverForADifferentAbsentOne() {
        let rows = IconsView.offlineRows(
            storeKeys: [safariByPath],
            running: [app("com.apple.Terminal", at: "/Applications/Utilities/Terminal.app")])
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: Wrappers

    /// Site-specific-browser wrappers share a bundle identifier but live at
    /// different paths, so one of them running says nothing about the others.
    ///
    /// This is the invariant the whole key design turns on. If `offlineRows` ever
    /// grew identifier matching for path-keyed entries, a running wrapper would
    /// silently suppress its sibling's row and the user would lose the only way to
    /// undo that icon.
    func testOneRunningWrapperDoesNotCoverItsSiblings() {
        let rows = IconsView.offlineRows(
            storeKeys: [.app(at: URL(fileURLWithPath: "/Applications/Claude ★.app")),
                        .app(at: URL(fileURLWithPath: "/Applications/CodeNomad.app"))],
            running: [app("com.google.Chrome", at: "/Applications/Claude ★.app")])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.bundleIdentifier, "/Applications/CodeNomad.app")
    }

    /// The other half: a running wrapper *does* cover the shared identifier, because
    /// a legacy entry filed under it is that same app from before the key change.
    func testARunningWrapperCoversTheSharedIdentifier() {
        let rows = IconsView.offlineRows(
            storeKeys: [.app(bundleIdentifier: "com.google.Chrome")],
            running: [app("com.google.Chrome", at: "/Applications/Claude ★.app")])
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: Entries Zap has nothing to say about

    /// Jetty and Top Drawer can key a file or a link; Zap can't draw either and has
    /// nowhere to put them. They belong to Pict's list, not this one.
    func testFileAndLinkEntriesGetNoRow() {
        let rows = IconsView.offlineRows(
            storeKeys: [.file(at: URL(fileURLWithPath: "/Users/someone/Notes.txt")),
                        .url(URL(string: "https://example.com")!)],
            running: [])
        XCTAssertTrue(rows.isEmpty)
    }
}

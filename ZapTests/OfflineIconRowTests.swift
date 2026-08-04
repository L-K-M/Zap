import Foundation
import XCTest
@testable import Zap

/// Which manifest entries get a row of their own in the Icons tab.
///
/// The rule has to see past the key change: an icon set before overrides were
/// keyed by path is still filed under the bundle identifier, and treating that as
/// a different app puts a second row on screen for one already in the list.
final class OfflineIconRowTests: XCTestCase {

    private func app(_ bundleID: String, at path: String? = nil) -> AppInfo {
        AppInfo(bundleIdentifier: bundleID, name: bundleID, processIdentifier: 1,
                bundleURL: path.map { URL(fileURLWithPath: $0) })
    }

    // MARK: The upgrade path

    /// The regression this exists for. Safari is running and its icon was set
    /// before the key change, so the manifest still says `com.apple.Safari` — which
    /// must not read as an absent app.
    func testALegacyEntryForARunningAppGetsNoSecondRow() {
        let keys = IconsView.offlineKeys(
            manifestKeys: ["com.apple.Safari"],
            running: [app("com.apple.Safari", at: "/Applications/Safari.app")])
        XCTAssertTrue(keys.isEmpty)
    }

    /// The same app once it has been re-saved under the new key.
    func testAPathEntryForARunningAppGetsNoSecondRow() {
        let keys = IconsView.offlineKeys(
            manifestKeys: ["/Applications/Safari.app"],
            running: [app("com.apple.Safari", at: "/Applications/Safari.app")])
        XCTAssertTrue(keys.isEmpty)
    }

    /// And mid-upgrade, with both present, it is still one app.
    func testBothKeysForOneRunningAppGetNoRows() {
        let keys = IconsView.offlineKeys(
            manifestKeys: ["com.apple.Safari", "/Applications/Safari.app"],
            running: [app("com.apple.Safari", at: "/Applications/Safari.app")])
        XCTAssertTrue(keys.isEmpty)
    }

    // MARK: Still listing what it should

    /// The reason the offline list exists: an app that isn't running would
    /// otherwise be unreachable, and the user could never undo its icon.
    func testAnAbsentAppStillGetsARow() {
        let keys = IconsView.offlineKeys(
            manifestKeys: ["com.apple.Safari", "/Applications/Gone.app"],
            running: [app("com.apple.Mail", at: "/Applications/Mail.app")])
        XCTAssertEqual(Set(keys), ["com.apple.Safari", "/Applications/Gone.app"])
    }

    /// Wrappers sharing an identifier are separate apps, so one of them running
    /// says nothing about the others.
    func testOneRunningWrapperDoesNotCoverItsSiblings() {
        let keys = IconsView.offlineKeys(
            manifestKeys: ["/Applications/Claude ★.app", "/Applications/CodeNomad.app"],
            running: [app("com.google.Chrome", at: "/Applications/Claude ★.app")])
        XCTAssertEqual(keys, ["/Applications/CodeNomad.app"])
    }

    /// …but a running wrapper *does* cover the shared identifier, because that is
    /// a key it could legitimately have been stored under.
    func testARunningWrapperCoversTheSharedIdentifier() {
        let keys = IconsView.offlineKeys(
            manifestKeys: ["com.google.Chrome"],
            running: [app("com.google.Chrome", at: "/Applications/Claude ★.app")])
        XCTAssertTrue(keys.isEmpty)
    }

    func testAnAppWithNoKnownPathIsMatchedByItsIdentifier() {
        let keys = IconsView.offlineKeys(manifestKeys: ["com.apple.Safari"],
                                         running: [app("com.apple.Safari")])
        XCTAssertTrue(keys.isEmpty)
    }
}

import Foundation
import XCTest
@testable import Zap

/// The keying rule that stops one custom icon painting several apps.
final class IconIdentityTests: XCTestCase {

    private func chromeWrapper(_ name: String) -> IconIdentity {
        IconIdentity(bundleIdentifier: "com.google.Chrome",
                     bundleURL: URL(fileURLWithPath: "/Applications/\(name).app/Contents/Resources/\(name).app"))
    }

    // MARK: The bug

    /// The reported case: three site-specific-browser wrappers, three separate app
    /// bundles, one bundle identifier between them. Keyed by identifier they were
    /// the same app, so one icon covered all three.
    func testWrappersSharingAnIdentifierGetSeparateKeys() {
        let keys = ["Claude ★", "CodeNomad", "CodeNomad Dev"].map { chromeWrapper($0).storageKey }
        XCTAssertEqual(Set(keys).count, 3, "each wrapper needs its own key")
        XCTAssertFalse(keys.contains("com.google.Chrome"))
    }

    /// And the browser they borrowed the identifier from is a fourth app again.
    func testTheRealBrowserIsDistinctFromItsWrappers() {
        let chrome = IconIdentity(bundleIdentifier: "com.google.Chrome",
                                  bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"))
        XCTAssertNotEqual(chrome.storageKey, chromeWrapper("Claude ★").storageKey)
    }

    // MARK: Keys

    func testStorageKeyIsThePathWhenOneIsKnown() {
        let identity = IconIdentity(bundleIdentifier: "com.apple.Safari",
                                    bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"))
        XCTAssertEqual(identity.storageKey, "/Applications/Safari.app")
    }

    /// An app Zap knows only by identifier — a manifest entry whose app isn't
    /// running — still has a key, and it is the identifier.
    func testStorageKeyFallsBackToTheIdentifier() {
        let identity = IconIdentity(bundleIdentifier: "com.apple.Safari")
        XCTAssertEqual(identity.storageKey, "com.apple.Safari")
        XCTAssertNil(identity.legacyKey)
        XCTAssertEqual(identity.lookupKeys, ["com.apple.Safari"])
    }

    /// Every icon set before overrides were keyed by path is still found, which is
    /// why none of them had to be migrated.
    func testLookupFallsBackToTheOlderIdentifierKey() {
        let identity = IconIdentity(bundleIdentifier: "com.apple.Safari",
                                    bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"))
        XCTAssertEqual(identity.lookupKeys, ["/Applications/Safari.app", "com.apple.Safari"])
        XCTAssertEqual(identity.legacyKey, "com.apple.Safari")
    }

    func testPathsAreStandardisedSoTheSameAppKeysTheSameWay() {
        let plain = IconIdentity(bundleIdentifier: "a.b",
                                 bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"))
        let noisy = IconIdentity(bundleIdentifier: "a.b",
                                 bundleURL: URL(fileURLWithPath: "/Applications/./Safari.app"))
        XCTAssertEqual(plain.storageKey, noisy.storageKey)
    }

    // MARK: Reading a key back

    func testPathKeysAreTellableFromIdentifiers() {
        XCTAssertTrue(IconIdentity.isPath("/Applications/Claude ★.app"))
        XCTAssertFalse(IconIdentity.isPath("com.google.Chrome"))
        XCTAssertFalse(IconIdentity.isPath(""))
    }

    /// Settings lists manifest entries whose apps aren't running. A path key has to
    /// yield the app's own name — asking `NSWorkspace` for `com.google.Chrome`
    /// would label all three wrappers "Google Chrome".
    func testAPathKeyYieldsTheAppsOwnName() {
        XCTAssertEqual(
            IconIdentity.displayName(forPathKey: "/Applications/Claude ★.app/Contents/Resources/Claude ★.app"),
            "Claude ★")
        XCTAssertEqual(IconIdentity.displayName(forPathKey: "/Applications/CodeNomad Dev.app"),
                       "CodeNomad Dev")
        XCTAssertNil(IconIdentity.displayName(forPathKey: "com.google.Chrome"))
    }

    // MARK: Identity

    /// Used as a dictionary key by the resolver's cache, so two references to the
    /// same app have to land on the same entry.
    func testTheSameAppHashesTheSame() {
        let one = chromeWrapper("CodeNomad")
        let two = chromeWrapper("CodeNomad")
        XCTAssertEqual(one, two)
        XCTAssertEqual(Set([one, two]).count, 1)
    }

    func testDifferentAppsDoNotCollide() {
        XCTAssertEqual(Set([chromeWrapper("CodeNomad"), chromeWrapper("CodeNomad Dev")]).count, 2)
    }
}

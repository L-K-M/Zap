import AppKit
import PictKit
import XCTest
@testable import Zap

/// What stayed in Zap after the icon subsystem moved to `PictKit` and Pict.
///
/// The pipeline itself — classification, normalisation, validation, the store —
/// is tested in the package that now owns it. These are the seams on Zap's side:
/// the preference that selects a rung, the identity an icon is looked up by, and
/// the promise that swapping artwork can't perturb the switcher's ordering.
///
/// Split out of the old `IconRendererTests`, which covered both halves before
/// there was a boundary to be on either side of.
final class IconSubstitutionTests: XCTestCase {

    // MARK: The preference

    func testDefaultSourceModeMatchesTheRunningSystem() {
        XCTAssertEqual(IconSourceMode.systemDefault,
                       IconSourceMode.isSquircleJailed ? .original : .system)
    }

    func testSourceModeSurvivesAPreferencesRoundTrip() {
        let suite = "com.zapapp.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = Preferences(defaults: defaults)
        preferences.iconSourceMode = .originalPlusCustom
        XCTAssertEqual(Preferences(defaults: defaults).iconSourceMode, .originalPlusCustom)
    }

    func testUnknownStoredSourceModeFallsBackToTheDefault() {
        let suite = "com.zapapp.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("telepathy", forKey: "iconSourceMode")
        XCTAssertEqual(Preferences(defaults: defaults).iconSourceMode, IconSourceMode.systemDefault)
    }

    // MARK: Identity

    /// The reason overrides are keyed by path. Site-specific-browser wrappers ship
    /// one bundle per site and every one reports the browser's identifier, so an
    /// identifier-first ladder would paint all three with one icon.
    func testWrappersSharingABundleIdentifierGetDifferentKeys() {
        let claude = AppInfo(bundleIdentifier: "com.google.Chrome", name: "Claude",
                             processIdentifier: 1,
                             bundleURL: URL(fileURLWithPath: "/Applications/Claude.app"))
        let nomad = AppInfo(bundleIdentifier: "com.google.Chrome", name: "CodeNomad",
                            processIdentifier: 2,
                            bundleURL: URL(fileURLWithPath: "/Applications/CodeNomad.app"))

        XCTAssertNotEqual(claude.storeKey, nomad.storeKey)
        XCTAssertNotEqual(claude.mruKey, nomad.mruKey)
    }

    /// MRU keys are persisted, and every one stored before the shared store existed
    /// is bare. If `mruKey` ever gained the store's `kind:` prefix, none of them
    /// would match on upgrade and the user's switcher order would silently reset.
    ///
    /// This is not hypothetical: it shipped in an earlier commit on this branch and
    /// `SwitcherSelectionTests` caught it.
    func testTheMRUKeyCarriesNoStorePrefix() {
        let byPath = AppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari",
                             processIdentifier: 1,
                             bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"))
        XCTAssertEqual(byPath.mruKey, "/Applications/Safari.app")

        let byIdentifier = AppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari",
                                   processIdentifier: 1)
        XCTAssertEqual(byIdentifier.mruKey, "com.apple.Safari")

        for key in [byPath.mruKey, byIdentifier.mruKey] {
            XCTAssertFalse(key.hasPrefix("app:"))
            XCTAssertFalse(key.hasPrefix("bundleID:"))
        }
    }

    /// The store key and the MRU key are the same identity in two renderings, and
    /// the fallback to a bare identifier is documented as unreachable —
    /// `AppInfo.bundleIdentifier` is non-optional, so the lookup ladder always has
    /// at least its identifier rung. This asserts both, because if either stopped
    /// holding, two wrappers would collapse onto one MRU entry.
    func testTheStoreKeyIsTheMRUKeyWithItsKindPrefix() throws {
        for url in [URL(fileURLWithPath: "/Applications/Safari.app"), nil] {
            let app = AppInfo(bundleIdentifier: "com.apple.Safari", name: "Safari",
                              processIdentifier: 1, bundleURL: url)
            // Same identity, two renderings: the store wants the discriminated
            // form, the MRU wants the bare one. `XCTUnwrap` rather than a
            // `== true` comparison, so a nil key reports itself rather than
            // reading as a failed suffix check.
            let storeKey = try XCTUnwrap(app.storeKey)
            XCTAssertTrue(storeKey.hasSuffix(app.mruKey))
        }
    }

    // MARK: Substitution stays out of identity

    func testReplacingIconKeepsEverythingElse() {
        let original = AppInfo(bundleIdentifier: "a.b", name: "Thing",
                               processIdentifier: 42, icon: nil, isHidden: true)
        let replacement = NSImage(size: NSSize(width: 10, height: 10))
        let substituted = original.replacingIcon(replacement)

        XCTAssertEqual(substituted.bundleIdentifier, "a.b")
        XCTAssertEqual(substituted.name, "Thing")
        XCTAssertEqual(substituted.processIdentifier, 42)
        XCTAssertTrue(substituted.isHidden)
        XCTAssertTrue(substituted.icon === replacement)
    }

    /// `==` ignores the icon, so swapping artwork can't perturb selection or MRU.
    func testReplacingIconDoesNotChangeIdentity() {
        let original = AppInfo(bundleIdentifier: "a.b", name: "Thing", processIdentifier: 42)
        let substituted = original.replacingIcon(NSImage(size: NSSize(width: 10, height: 10)))

        XCTAssertEqual(original, substituted)
        XCTAssertEqual(original.id, substituted.id)
    }

    // MARK: The boundary with PictKit

    /// The normaliser's canvas and the row's image frame must agree, or the cached
    /// bitmap stops filling the frame it is drawn into. The two now live in
    /// different modules, which is exactly why the agreement needs asserting: a
    /// change to either one can no longer be seen from the other.
    func testTheRowMetricsAgreeWithTheNormalisersCanvas() {
        for bleed in [0.0, 0.05, 0.08, 0.15] {
            XCTAssertEqual(IconNormalizer.canvasExtent(targetExtent: 80, bleed: bleed),
                           Double(IconRowMetrics.imageExtent(iconSize: 80, bleed: CGFloat(bleed))),
                           accuracy: 0.0001)
        }
    }

    /// And that the two ceilings match, for the same reason.
    func testTheBleedCeilingsMatch() {
        XCTAssertEqual(IconNormalizer.maximumBleed, Double(IconRowMetrics.maximumBleed))
    }
}

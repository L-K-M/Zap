import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import Zap

/// The parts of icon resolution that are pure functions. The cache itself needs a
/// live `Preferences`, `NSScreen` and a background queue, so its behaviour is on
/// the manual list in `UNJAILED.md §9`.
final class IconResolverTests: XCTestCase {

    // MARK: Cached size

    func testCachedPixelSizeFollowsTheBackingScale() {
        XCTAssertEqual(IconResolver.pixelSize(forIconSize: 80, scale: 2), 160)
        XCTAssertEqual(IconResolver.pixelSize(forIconSize: 128, scale: 2), 256)
        XCTAssertEqual(IconResolver.pixelSize(forIconSize: 256, scale: 2), 512)
    }

    func testCachedPixelSizeHasAFloor() {
        // A tiny icon-size setting must not cache something that looks awful the
        // moment the user drags the slider back up.
        XCTAssertEqual(IconResolver.pixelSize(forIconSize: 24, scale: 1),
                       IconImageValidator.Limits.warnBelowPixels)
    }

    func testCachedPixelSizeRoundsUp() {
        XCTAssertEqual(IconResolver.pixelSize(forIconSize: 100.5, scale: 1.5), 151)
    }

    // MARK: Downsampling

    func testDownsampleShrinksToTheRequestedEdge() {
        let image = IconTestSupport.makeImage(width: 1024, height: 1024)
        let result = IconResolver.downsample(image, longestEdge: 160)
        XCTAssertEqual(result.width, 160)
        XCTAssertEqual(result.height, 160)
    }

    func testDownsampleKeepsTheAspectRatio() {
        let image = IconTestSupport.makeImage(width: 800, height: 400)
        let result = IconResolver.downsample(image, longestEdge: 200)
        XCTAssertEqual(result.width, 200)
        XCTAssertEqual(result.height, 100)
    }

    func testDownsampleNeverUpscales() {
        let image = IconTestSupport.makeImage(width: 64, height: 64)
        let result = IconResolver.downsample(image, longestEdge: 512)
        XCTAssertEqual(result.width, 64)
    }

    // MARK: Corner masking

    /// The reason full-bleed artwork is classified separately: un-masked, a modern
    /// square icon would be the only hard-cornered thing in the row.
    func testMaskingCornersRoundsOffAFullBleedSquare() {
        let square = IconTestSupport.makeImage(width: 256, height: 256)
        XCTAssertEqual(IconShapeClassifier.classify(square), .fullBleed)

        let masked = IconResolver.maskingCorners(
            square, radiusFraction: IconResolver.fullBleedCornerRadiusFraction)
        XCTAssertEqual(IconShapeClassifier.classify(masked), .roundedSquare)
        XCTAssertEqual(masked.width, 256)
    }

    func testMaskingCornersWithNoRadiusLeavesTheShapeAlone() {
        let square = IconTestSupport.makeImage(width: 128, height: 128)
        let masked = IconResolver.maskingCorners(square, radiusFraction: 0)
        XCTAssertEqual(IconShapeClassifier.classify(masked), .fullBleed)
    }

    // MARK: Source modes

    func testSourceModeCapabilities() {
        XCTAssertFalse(IconSourceMode.system.usesBundleArtwork)
        XCTAssertFalse(IconSourceMode.system.usesCustomIcons)

        XCTAssertTrue(IconSourceMode.original.usesBundleArtwork)
        XCTAssertFalse(IconSourceMode.original.usesCustomIcons)

        XCTAssertTrue(IconSourceMode.originalPlusCustom.usesBundleArtwork)
        XCTAssertTrue(IconSourceMode.originalPlusCustom.usesCustomIcons)
    }

    /// Un-jailing only defaults on where the system actually jails icons.
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
}

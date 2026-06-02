import XCTest
import AppKit
@testable import Zap

final class PreferencesTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.zapapp.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsWhenEmpty() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.excludedBundleIDs.isEmpty)
        XCTAssertEqual(prefs.backgroundColorHex, Preferences.Default.backgroundColorHex)
        XCTAssertEqual(prefs.iconSize, Preferences.Default.iconSize)
        XCTAssertEqual(prefs.highlightCornerRadius, Preferences.Default.highlightCornerRadius)
        XCTAssertEqual(prefs.contentPadding, Preferences.Default.contentPadding)
        XCTAssertTrue(prefs.showAppName)
        XCTAssertFalse(prefs.showWindowPreviews)
    }

    func testGradientBackgroundDefaults() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertFalse(prefs.useGradientBackground)
        XCTAssertEqual(prefs.gradientColorHex, Preferences.Default.gradientColorHex)
        XCTAssertEqual(prefs.gradientAngle, Preferences.Default.gradientAngle)
    }

    func testGradientBackgroundRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.useGradientBackground = true
        prefs.gradientColorHex = "#445566"
        prefs.gradientAngle = 135

        let reloaded = Preferences(defaults: defaults)
        XCTAssertTrue(reloaded.useGradientBackground)
        XCTAssertEqual(reloaded.gradientColorHex, "#445566")
        XCTAssertEqual(reloaded.gradientAngle, 135)
    }

    func testGradientAngleIsNormalizedIntoRange() {
        defaults.set(450.0, forKey: "gradientAngle")
        XCTAssertEqual(Preferences(defaults: defaults).gradientAngle, 90)

        defaults.set(-90.0, forKey: "gradientAngle")
        XCTAssertEqual(Preferences(defaults: defaults).gradientAngle, 270)

        defaults.set(Double.nan, forKey: "gradientAngle")
        XCTAssertEqual(Preferences(defaults: defaults).gradientAngle, 0)
    }

    func testDecorationDefaults() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.decorationStyle, .none)
        XCTAssertEqual(prefs.decorationPosition, Preferences.Default.decorationPosition)
        XCTAssertEqual(prefs.decorationOpacity, Preferences.Default.decorationOpacity)
        XCTAssertEqual(prefs.decorationSize, Preferences.Default.decorationSize)
    }

    func testDecorationRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.decorationStyle = .zxSpectrum
        prefs.decorationPosition = .topLeading
        prefs.decorationOpacity = 0.5
        prefs.decorationSize = 18

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.decorationStyle, .zxSpectrum)
        XCTAssertEqual(reloaded.decorationPosition, .topLeading)
        XCTAssertEqual(reloaded.decorationOpacity, 0.5)
        XCTAssertEqual(reloaded.decorationSize, 18)
    }

    func testOutOfRangeDecorationOpacityIsClamped() {
        defaults.set(3.0, forKey: "decorationOpacity")
        XCTAssertEqual(Preferences(defaults: defaults).decorationOpacity, 1)
        defaults.set(-1.0, forKey: "decorationOpacity")
        XCTAssertEqual(Preferences(defaults: defaults).decorationOpacity, 0)
    }

    func testOutOfRangeDecorationSizeIsClamped() {
        defaults.set(500.0, forKey: "decorationSize")
        XCTAssertLessThanOrEqual(Preferences(defaults: defaults).decorationSize, 30)
        defaults.set(0.0, forKey: "decorationSize")
        XCTAssertGreaterThanOrEqual(Preferences(defaults: defaults).decorationSize, 4)
    }

    func testInvalidStoredDecorationFallsBackToDefault() {
        defaults.set("disco-ball", forKey: "decorationStyle")
        defaults.set("middle", forKey: "decorationPosition")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.decorationStyle, Preferences.Default.decorationStyle)
        XCTAssertEqual(prefs.decorationPosition, Preferences.Default.decorationPosition)
    }

    func testInvalidStoredGradientColorFallsBackToDefault() {
        defaults.set("not-a-color", forKey: "gradientColorHex")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.gradientColorHex, Preferences.Default.gradientColorHex)
    }

    func testShowWindowPreviewsRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.showWindowPreviews = true

        let reloaded = Preferences(defaults: defaults)
        XCTAssertTrue(reloaded.showWindowPreviews)
    }

    func testExclusionsRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.setExcluded(true, bundleID: "com.apple.Safari")
        prefs.setExcluded(true, bundleID: "com.apple.Mail")
        prefs.setExcluded(false, bundleID: "com.apple.Safari")

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.excludedBundleIDs, ["com.apple.Mail"])
    }

    func testAppearanceRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        prefs.backgroundColorHex = "#112233"
        prefs.highlightColorHex = "#AABBCC"
        prefs.iconSize = 96
        prefs.cornerRadius = 24
        prefs.showAppName = false

        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.backgroundColorHex, "#112233")
        XCTAssertEqual(reloaded.highlightColorHex, "#AABBCC")
        XCTAssertEqual(reloaded.iconSize, 96)
        XCTAssertEqual(reloaded.cornerRadius, 24)
        XCTAssertFalse(reloaded.showAppName)
    }

    func testColorHexParsingRoundTrip() {
        let color = NSColor(hex: "#0A84FF")
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.hexString, "#0A84FF")
    }

    func testColorHexInvalidReturnsNil() {
        XCTAssertNil(NSColor(hex: "nothex"))
        XCTAssertNil(NSColor(hex: "#12"))
    }

    func testInvalidStoredColorFallsBackToDefault() {
        defaults.set("not-a-color", forKey: "backgroundColorHex")
        defaults.set("#GGGGGG", forKey: "highlightColorHex")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.backgroundColorHex, Preferences.Default.backgroundColorHex)
        XCTAssertEqual(prefs.highlightColorHex, Preferences.Default.highlightColorHex)
    }

    func testOutOfRangeOpacityIsClamped() {
        defaults.set(-2.0, forKey: "backgroundOpacity")
        defaults.set(5.0, forKey: "highlightOpacity")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.backgroundOpacity, 0)
        XCTAssertEqual(prefs.highlightOpacity, 1)
    }

    func testOutOfRangeIconSizeAndDelaysAreClamped() {
        defaults.set(100_000.0, forKey: "iconSize")
        defaults.set(-50.0, forKey: "showDelayMs")
        defaults.set(99_999.0, forKey: "windowDwellMs")
        let prefs = Preferences(defaults: defaults)
        XCTAssertLessThanOrEqual(prefs.iconSize, 256)
        XCTAssertGreaterThanOrEqual(prefs.showDelayMs, 0)
        XCTAssertLessThanOrEqual(prefs.windowDwellMs, 5000)
    }

    func testOutOfRangeLayoutValuesAreClamped() {
        defaults.set(-10.0, forKey: "contentPadding")
        defaults.set(9_999.0, forKey: "highlightCornerRadius")
        let prefs = Preferences(defaults: defaults)
        XCTAssertGreaterThanOrEqual(prefs.contentPadding, 0)
        XCTAssertLessThanOrEqual(prefs.highlightCornerRadius, 64)
    }

    func testNonFiniteValueFallsBackToDefault() {
        defaults.set(Double.nan, forKey: "iconSize")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.iconSize, Preferences.Default.iconSize)
    }
}

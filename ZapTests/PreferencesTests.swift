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
        XCTAssertTrue(prefs.showAppName)
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

    func testNonFiniteValueFallsBackToDefault() {
        defaults.set(Double.nan, forKey: "iconSize")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.iconSize, Preferences.Default.iconSize)
    }
}

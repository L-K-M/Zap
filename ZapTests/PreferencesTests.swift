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
}

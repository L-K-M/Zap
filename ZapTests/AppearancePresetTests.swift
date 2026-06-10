import XCTest
@testable import Zap

final class AppearancePresetTests: XCTestCase {

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

    func testJSONRoundTrip() throws {
        let preset = AppearancePreset.vaporwave
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(AppearancePreset.self, from: data)
        XCTAssertEqual(decoded, preset)
    }

    func testSnapshotCapturesCurrentSettings() {
        let prefs = Preferences(defaults: defaults)
        prefs.backgroundColorHex = "#102030"
        prefs.iconSize = 96
        prefs.crtEnabled = true
        prefs.decorationStyle = .amiga

        let preset = AppearancePreset(name: "Snap", from: prefs)
        XCTAssertEqual(preset.name, "Snap")
        XCTAssertEqual(preset.backgroundColorHex, "#102030")
        XCTAssertEqual(preset.iconSize, 96)
        XCTAssertTrue(preset.crtEnabled)
        XCTAssertEqual(preset.decorationStyle, DecorationStyle.amiga.rawValue)
    }

    func testApplySetsEverySetting() {
        let prefs = Preferences(defaults: defaults)
        AppearancePreset.amiga.apply(to: prefs)

        XCTAssertEqual(prefs.decorationStyle, .amigaPixel)
        XCTAssertTrue(prefs.crtEnabled)
        XCTAssertEqual(prefs.crtIntensity, 0.7, accuracy: 0.0001)
        XCTAssertEqual(prefs.highlightColorHex, "#FF6F00")
        XCTAssertFalse(prefs.useGradientBackground)
    }

    func testApplyIsAReversibleRoundTrip() {
        let prefs = Preferences(defaults: defaults)
        // Start from a non-default look, snapshot it, scramble, then re-apply.
        AppearancePreset.zxNight.apply(to: prefs)
        let snapshot = AppearancePreset(name: "x", from: prefs)

        AppearancePreset.classic.apply(to: prefs)
        snapshot.apply(to: prefs)

        XCTAssertEqual(prefs.backgroundColorHex, AppearancePreset.zxNight.backgroundColorHex)
        XCTAssertEqual(prefs.decorationStyle.rawValue, AppearancePreset.zxNight.decorationStyle)
        XCTAssertEqual(prefs.gradientAngle, AppearancePreset.zxNight.gradientAngle)
        XCTAssertEqual(prefs.crtIntensity, AppearancePreset.zxNight.crtIntensity, accuracy: 0.0001)
    }

    func testApplyClampsOutOfRangeValues() {
        var preset = AppearancePreset.classic
        preset.iconSize = 100_000
        preset.crtIntensity = 5
        preset.backgroundOpacity = -3
        preset.gradientAngle = 450

        let prefs = Preferences(defaults: defaults)
        preset.apply(to: prefs)

        XCTAssertLessThanOrEqual(prefs.iconSize, 256)
        XCTAssertEqual(prefs.crtIntensity, 1)
        XCTAssertEqual(prefs.backgroundOpacity, 0)
        XCTAssertEqual(prefs.gradientAngle, 90)   // 450 wraps into [0, 360)
    }

    func testApplyRejectsInvalidColorAndStyle() {
        var preset = AppearancePreset.classic
        preset.backgroundColorHex = "not-a-color"
        preset.decorationStyle = "disco-ball"

        let prefs = Preferences(defaults: defaults)
        preset.apply(to: prefs)

        XCTAssertEqual(prefs.backgroundColorHex, Preferences.Default.backgroundColorHex)
        XCTAssertEqual(prefs.decorationStyle, Preferences.Default.decorationStyle)
    }
}

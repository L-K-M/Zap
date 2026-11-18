import XCTest
import LiveryKit
@testable import Zap

final class AppearancePresetTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ch.lkmc.Zap.tests.\(UUID().uuidString)"
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

    func testMidnightJSONRoundTrip() throws {
        let preset = AppearancePreset.midnight
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(AppearancePreset.self, from: data)

        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.name, "Midnight")
        XCTAssertEqual(decoded.backgroundColorHex, "#111827")
        XCTAssertTrue(decoded.useGradientBackground)
        XCTAssertEqual(decoded.gradientColorHex, "#172554")
        XCTAssertEqual(decoded.gradientAngle, 30)
        XCTAssertEqual(decoded.highlightColorHex, "#60A5FA")
        XCTAssertEqual(decoded.highlightOpacity, 0.45, accuracy: 0.0001)
        XCTAssertEqual(decoded.labelColorHex, "#F8FAFC")
        XCTAssertEqual(decoded.backgroundOpacity, 0.9, accuracy: 0.0001)
        XCTAssertFalse(decoded.crtEnabled)
        XCTAssertEqual(decoded.decorationStyle, DecorationStyle.none.rawValue)
    }

    func testMidnightApplyRoundTripPreservesFixture() {
        let prefs = Preferences(defaults: defaults)
        AppearancePreset.midnight.apply(to: prefs)
        let snapshot = AppearancePreset(name: "Midnight", from: prefs)

        XCTAssertEqual(snapshot, AppearancePreset.midnight)
    }

    func testMidnightUsesClassicGeometry() {
        let preset = AppearancePreset.midnight

        XCTAssertEqual(preset.iconSize, AppearancePreset.classic.iconSize)
        XCTAssertEqual(preset.cornerRadius, AppearancePreset.classic.cornerRadius)
        XCTAssertEqual(preset.highlightCornerRadius, AppearancePreset.classic.highlightCornerRadius)
        XCTAssertEqual(preset.contentPadding, AppearancePreset.classic.contentPadding)
        XCTAssertEqual(preset.showAppName, AppearancePreset.classic.showAppName)
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

// MARK: - Importing sibling themes

/// Zap reads Jetty and Invoque theme files through Livery's `ThemeSnapshot`,
/// and its own exports must stay readable by that shared reader.
final class AppearancePresetImportTests: XCTestCase {

    private func decode(_ json: String) -> AppearancePreset? {
        AppearancePreset.decode(from: Data(json.utf8))
    }

    func testCompleteZapThemeDecodesAsItself() throws {
        let data = try JSONEncoder().encode(AppearancePreset.zxNight)
        XCTAssertEqual(AppearancePreset.decode(from: data), AppearancePreset.zxNight)
    }

    /// The shared reader must recognise every built-in theme Zap exports and
    /// read back the settings the siblings understand.
    func testZapExportsAreReadableByTheSharedReader() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for preset in AppearancePreset.builtIns {
            let theme = try XCTUnwrap(ThemeSnapshot(themeData: try encoder.encode(preset)), preset.name)
            XCTAssertEqual(theme.format, .zap, preset.name)
            XCTAssertEqual(theme.name, preset.name)
            XCTAssertEqual(theme.material, preset.useGradientBackground ? .gradient : .solid, preset.name)
            XCTAssertEqual(theme.tintHex, preset.backgroundColorHex, preset.name)
            XCTAssertEqual(theme.gradientHex, preset.gradientColorHex, preset.name)
            XCTAssertEqual(theme.highlightHex, preset.highlightColorHex, preset.name)
            XCTAssertEqual(theme.labelHex, preset.labelColorHex, preset.name)
            XCTAssertEqual(theme.showsLabels, preset.showAppName, preset.name)
            XCTAssertEqual(theme.iconSize, preset.iconSize, preset.name)
            XCTAssertEqual(theme.decorationStyle?.rawValue, preset.decorationStyle, preset.name)
            XCTAssertEqual(theme.crtIntensity, preset.crtIntensity, preset.name)
        }
    }

    /// Jetty's built-in "Vapor" theme as Jetty exports it.
    func testImportsJettyTheme() throws {
        let preset = try XCTUnwrap(decode(##"""
        {"accentGlow": true, "backgroundOpacity": 0.7, "cornerRadius": 24,
         "crtEnabled": true, "crtIntensity": 0.5, "decorationOpacity": 1,
         "decorationPosition": "topTrailing", "decorationSize": 12,
         "decorationStyle": "vaporwave", "glyphHex": "#FFFFFF", "gradientAngle": 60,
         "gradientHex": "#8795E8", "iconSize": 50, "indicatorHex": "#FFFFFF",
         "indicatorStyle": "dot", "magnification": 1.6, "magnificationEnabled": true,
         "material": "gradient", "name": "Vapor", "showLabels": false,
         "tileSpacing": 10, "tintHex": "#FF6AD5"}
        """##))

        let d = Preferences.Default.self
        XCTAssertEqual(preset.name, "Vapor")
        XCTAssertTrue(preset.useGradientBackground)
        XCTAssertEqual(preset.backgroundColorHex, "#FF6AD5")
        XCTAssertEqual(preset.gradientColorHex, "#8795E8")
        XCTAssertEqual(preset.gradientAngle, 60)
        XCTAssertEqual(preset.backgroundOpacity, 0.7)
        XCTAssertEqual(preset.cornerRadius, 24)
        XCTAssertEqual(preset.iconSize, 50)
        XCTAssertFalse(preset.showAppName)
        XCTAssertEqual(preset.decorationStyle, DecorationStyle.vaporwave.rawValue)
        XCTAssertTrue(preset.crtEnabled)
        // Jetty has no selection highlight or label color: Zap's defaults.
        XCTAssertEqual(preset.highlightColorHex, d.highlightColorHex)
        XCTAssertEqual(preset.labelColorHex, d.labelColorHex)
        XCTAssertEqual(preset.contentPadding, d.contentPadding)
    }

    /// Invoque's built-in "Summon" theme as Invoque exports it.
    func testImportsInvoqueTheme() throws {
        let preset = try XCTUnwrap(decode(##"""
        {"adaptiveAccent": true, "backgroundOpacity": 0.9, "cornerRadius": 16,
         "crtEnabled": false, "crtIntensity": 0.5, "decorationOpacity": 1,
         "decorationPosition": "topTrailing", "decorationSize": 10,
         "decorationStyle": "none", "gradientAngle": 30, "gradientHex": "#2A1F4D",
         "highlightCornerRadius": 10, "highlightHex": "#B18CFF", "highlightOpacity": 0.4,
         "labelHex": "#EDE9FF", "material": "gradient", "name": "Summon",
         "tintHex": "#17122B", "typeface": "system"}
        """##))

        let d = Preferences.Default.self
        XCTAssertEqual(preset.name, "Summon")
        XCTAssertTrue(preset.useGradientBackground)
        XCTAssertEqual(preset.backgroundColorHex, "#17122B")
        XCTAssertEqual(preset.highlightColorHex, "#B18CFF")
        XCTAssertEqual(preset.highlightOpacity, 0.4)
        XCTAssertEqual(preset.highlightCornerRadius, 10)
        XCTAssertEqual(preset.labelColorHex, "#EDE9FF")
        // Invoque has no icon size or app-name toggle: Zap's defaults.
        XCTAssertEqual(preset.iconSize, d.iconSize)
        XCTAssertEqual(preset.showAppName, d.showAppName)
    }

    /// On system glass the sibling's tint and opacity were never visible, so
    /// they would paint a background its author never saw.
    func testGlassThemeKeepsZapsBackground() throws {
        let preset = try XCTUnwrap(decode(##"""
        {"material": "liquidGlass", "tintHex": "#0A7AFF", "backgroundOpacity": 0.55,
         "tileSpacing": 8, "cornerRadius": 22}
        """##))

        let d = Preferences.Default.self
        XCTAssertFalse(preset.useGradientBackground)
        XCTAssertEqual(preset.backgroundColorHex, d.backgroundColorHex)
        XCTAssertEqual(preset.backgroundOpacity, d.backgroundOpacity)
        XCTAssertEqual(preset.cornerRadius, 22)
    }

    func testTintedGlassKeepsTheSiblingsTint() throws {
        let preset = try XCTUnwrap(decode(##"{"material": "glassTinted", "tintHex": "#336699", "tileSpacing": 8}"##))
        XCTAssertEqual(preset.backgroundColorHex, "#336699")
        XCTAssertFalse(preset.useGradientBackground)
    }

    /// A Zap file missing fields used to fail the whole import; it now maps
    /// what it has.
    func testPartialZapThemeImportsWithDefaults() throws {
        let preset = try XCTUnwrap(decode(##"{"name": "Bits", "backgroundColorHex": "#202020", "gradientAngle": "45"}"##))

        let d = Preferences.Default.self
        XCTAssertEqual(preset.name, "Bits")
        XCTAssertEqual(preset.backgroundColorHex, "#202020")
        XCTAssertEqual(preset.gradientAngle, d.gradientAngle, "a wrong-typed field falls back")
        XCTAssertEqual(preset.contentPadding, d.contentPadding)
    }

    func testUnrelatedJSONIsRejected() {
        XCTAssertNil(decode(##"{"tabs": [], "version": 3}"##))
        XCTAssertNil(decode("[]"))
        XCTAssertNil(decode("not json"))
    }
}

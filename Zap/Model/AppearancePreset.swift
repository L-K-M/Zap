import AppKit

/// A named, shareable snapshot of every appearance setting. Serialized to a small
/// JSON file for export/import, and used for the built-in themes. Decoupled from
/// `Preferences` so it round-trips as plain data and can be unit-tested.
struct AppearancePreset: Codable, Equatable, Identifiable {
    var name: String
    var backgroundColorHex: String
    var useGradientBackground: Bool
    var gradientColorHex: String
    var gradientAngle: Double
    var decorationStyle: String
    var decorationPosition: String
    var decorationOpacity: Double
    var decorationSize: Double
    var crtEnabled: Bool
    var crtIntensity: Double
    var highlightColorHex: String
    var labelColorHex: String
    var backgroundOpacity: Double
    var highlightOpacity: Double
    var iconSize: Double
    var cornerRadius: Double
    var highlightCornerRadius: Double
    var contentPadding: Double
    var showAppName: Bool

    /// Presets are identified (and de-duplicated in menus) by name.
    var id: String { name }
}

// MARK: - Snapshot / apply

extension AppearancePreset {

    /// Captures the current appearance settings under `name`.
    init(name: String, from preferences: Preferences) {
        self.name = name
        backgroundColorHex = preferences.backgroundColorHex
        useGradientBackground = preferences.useGradientBackground
        gradientColorHex = preferences.gradientColorHex
        gradientAngle = preferences.gradientAngle
        decorationStyle = preferences.decorationStyle.rawValue
        decorationPosition = preferences.decorationPosition.rawValue
        decorationOpacity = preferences.decorationOpacity
        decorationSize = preferences.decorationSize
        crtEnabled = preferences.crtEnabled
        crtIntensity = preferences.crtIntensity
        highlightColorHex = preferences.highlightColorHex
        labelColorHex = preferences.labelColorHex
        backgroundOpacity = preferences.backgroundOpacity
        highlightOpacity = preferences.highlightOpacity
        iconSize = preferences.iconSize
        cornerRadius = preferences.cornerRadius
        highlightCornerRadius = preferences.highlightCornerRadius
        contentPadding = preferences.contentPadding
        showAppName = preferences.showAppName
    }

    /// Applies the preset, validating and clamping every value the same way
    /// `Preferences` does on load — so an imported (possibly hand-edited or
    /// stale) file can never push a setting out of range or set an invalid color.
    func apply(to preferences: Preferences) {
        preferences.backgroundColorHex = Self.validColor(backgroundColorHex, default: Preferences.Default.backgroundColorHex)
        preferences.useGradientBackground = useGradientBackground
        preferences.gradientColorHex = Self.validColor(gradientColorHex, default: Preferences.Default.gradientColorHex)
        preferences.gradientAngle = Self.normalizedAngle(gradientAngle)
        preferences.decorationStyle = DecorationStyle(rawValue: decorationStyle) ?? Preferences.Default.decorationStyle
        preferences.decorationPosition = DecorationPosition(rawValue: decorationPosition) ?? Preferences.Default.decorationPosition
        preferences.decorationOpacity = Self.clamp(decorationOpacity, 0, 1, Preferences.Default.decorationOpacity)
        preferences.decorationSize = Self.clamp(decorationSize, 4, 30, Preferences.Default.decorationSize)
        preferences.crtEnabled = crtEnabled
        preferences.crtIntensity = Self.clamp(crtIntensity, 0, 1, Preferences.Default.crtIntensity)
        preferences.highlightColorHex = Self.validColor(highlightColorHex, default: Preferences.Default.highlightColorHex)
        preferences.labelColorHex = Self.validColor(labelColorHex, default: Preferences.Default.labelColorHex)
        preferences.backgroundOpacity = Self.clamp(backgroundOpacity, 0, 1, Preferences.Default.backgroundOpacity)
        preferences.highlightOpacity = Self.clamp(highlightOpacity, 0, 1, Preferences.Default.highlightOpacity)
        preferences.iconSize = Self.clamp(iconSize, 24, 256, Preferences.Default.iconSize)
        preferences.cornerRadius = Self.clamp(cornerRadius, 0, 64, Preferences.Default.cornerRadius)
        preferences.highlightCornerRadius = Self.clamp(highlightCornerRadius, 0, 64, Preferences.Default.highlightCornerRadius)
        preferences.contentPadding = Self.clamp(contentPadding, 0, 60, Preferences.Default.contentPadding)
        preferences.showAppName = showAppName
    }

    // MARK: Validation (mirrors Preferences' own load-time validation)

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double, _ fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.min(Swift.max(value, lower), upper)
    }

    private static func validColor(_ hex: String, default fallback: String) -> String {
        NSColor(hex: hex) != nil ? hex : fallback
    }

    private static func normalizedAngle(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }
}

// MARK: - Built-in themes

extension AppearancePreset {

    /// A few ready-made themes shown in the Appearance settings.
    static let builtIns: [AppearancePreset] = [classic, zxNight, vaporwave, amiga]

    /// The shipping defaults, as a named preset.
    static let classic = AppearancePreset(
        name: "Classic",
        backgroundColorHex: Preferences.Default.backgroundColorHex,
        useGradientBackground: Preferences.Default.useGradientBackground,
        gradientColorHex: Preferences.Default.gradientColorHex,
        gradientAngle: Preferences.Default.gradientAngle,
        decorationStyle: Preferences.Default.decorationStyle.rawValue,
        decorationPosition: Preferences.Default.decorationPosition.rawValue,
        decorationOpacity: Preferences.Default.decorationOpacity,
        decorationSize: Preferences.Default.decorationSize,
        crtEnabled: Preferences.Default.crtEnabled,
        crtIntensity: Preferences.Default.crtIntensity,
        highlightColorHex: Preferences.Default.highlightColorHex,
        labelColorHex: Preferences.Default.labelColorHex,
        backgroundOpacity: Preferences.Default.backgroundOpacity,
        highlightOpacity: Preferences.Default.highlightOpacity,
        iconSize: Preferences.Default.iconSize,
        cornerRadius: Preferences.Default.cornerRadius,
        highlightCornerRadius: Preferences.Default.highlightCornerRadius,
        contentPadding: Preferences.Default.contentPadding,
        showAppName: true)

    static let zxNight = AppearancePreset(
        name: "ZX Night",
        backgroundColorHex: "#0B0B1A",
        useGradientBackground: true,
        gradientColorHex: "#1A1140",
        gradientAngle: 20,
        decorationStyle: DecorationStyle.zxSpectrum.rawValue,
        decorationPosition: DecorationPosition.topTrailing.rawValue,
        decorationOpacity: 1,
        decorationSize: 12,
        crtEnabled: true,
        crtIntensity: 0.5,
        highlightColorHex: "#00AEEF",
        labelColorHex: "#FFFFFF",
        backgroundOpacity: 0.7,
        highlightOpacity: 0.85,
        iconSize: 80,
        cornerRadius: 14,
        highlightCornerRadius: 12,
        contentPadding: 20,
        showAppName: true)

    static let vaporwave = AppearancePreset(
        name: "Vaporwave",
        backgroundColorHex: "#241B4B",
        useGradientBackground: true,
        gradientColorHex: "#3B2A6B",
        gradientAngle: 35,
        decorationStyle: DecorationStyle.vaporwave.rawValue,
        decorationPosition: DecorationPosition.topTrailing.rawValue,
        decorationOpacity: 1,
        decorationSize: 12,
        crtEnabled: true,
        crtIntensity: 0.6,
        highlightColorHex: "#FF6AD5",
        labelColorHex: "#FFFFFF",
        backgroundOpacity: 0.6,
        highlightOpacity: 0.8,
        iconSize: 80,
        cornerRadius: 20,
        highlightCornerRadius: 16,
        contentPadding: 20,
        showAppName: true)

    static let amiga = AppearancePreset(
        name: "Amiga",
        backgroundColorHex: "#1A1A1A",
        useGradientBackground: false,
        gradientColorHex: "#2C2C2C",
        gradientAngle: 0,
        // The pixel rendition: with the CRT scanlines below, the full retro look.
        decorationStyle: DecorationStyle.amigaPixel.rawValue,
        decorationPosition: DecorationPosition.topTrailing.rawValue,
        decorationOpacity: 1,
        decorationSize: 10,
        crtEnabled: true,
        crtIntensity: 0.7,
        highlightColorHex: "#FF6F00",
        labelColorHex: "#FFFFFF",
        backgroundOpacity: 0.55,
        highlightOpacity: 0.85,
        iconSize: 80,
        cornerRadius: 16,
        highlightCornerRadius: 14,
        contentPadding: 20,
        showAppName: true)
}

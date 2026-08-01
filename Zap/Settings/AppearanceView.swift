import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Color and size customization with a live preview of the overlay.
struct AppearanceView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(spacing: 0) {
            preview
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(previewBackground)

            Divider()

            Form {
                Section("Presets") {
                    Menu("Apply a built-in theme") {
                        ForEach(AppearancePreset.builtIns) { preset in
                            Button(preset.name) { preset.apply(to: preferences) }
                        }
                    }
                    HStack {
                        Button("Import…", action: importPreset)
                        Button("Export…", action: exportPreset)
                        Spacer()
                    }
                    Text("Apply a ready-made theme, or save the current look as a shareable .json file to import later or send to a friend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Colors") {
                    ColorPicker("Background", selection: colorBinding(\.backgroundColorHex), supportsOpacity: false)
                    Toggle("Gradient background", isOn: $preferences.useGradientBackground)
                    if preferences.useGradientBackground {
                        ColorPicker("Gradient end", selection: colorBinding(\.gradientColorHex), supportsOpacity: false)
                        HStack {
                            Text("Gradient direction")
                            Spacer()
                            Text("\(Int(preferences.gradientAngle.rounded()))°")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            AngleDial(angleDegrees: $preferences.gradientAngle)
                        }
                    }
                    sliderRow("Background opacity", value: $preferences.backgroundOpacity, range: 0...1)
                    ColorPicker("Highlight", selection: colorBinding(\.highlightColorHex), supportsOpacity: false)
                    sliderRow("Highlight opacity", value: $preferences.highlightOpacity, range: 0...1)
                    ColorPicker("App name text", selection: colorBinding(\.labelColorHex), supportsOpacity: false)
                }

                Section("Layout") {
                    sliderRow("Icon size", value: $preferences.iconSize, range: 48...128, step: 4)
                    sliderRow("Panel corner radius", value: $preferences.cornerRadius, range: 0...64, step: 1)
                    sliderRow("Highlight corner radius", value: $preferences.highlightCornerRadius, range: 0...64, step: 1)
                    sliderRow("Icon padding", value: $preferences.contentPadding, range: 0...60, step: 1)
                    Toggle("Show app name", isOn: $preferences.showAppName)
                }

                Section("Icon artwork") {
                    sliderRow("Bleed", value: $preferences.iconBleed,
                              range: 0...Double(IconRowMetrics.maximumBleed), step: 0.01)
                    Toggle("Trim transparent edges", isOn: $preferences.iconTrimTransparentEdges)
                    Toggle("Drop shadow", isOn: $preferences.iconShadow)
                    Text("Free-form icons are scaled to carry the same visual weight as square ones, which makes them wider — bleed is how far past the selection highlight they may go. Applies to un-jailed artwork; see the Icons tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Decoration") {
                    Picker("Style", selection: $preferences.decorationStyle) {
                        ForEach(DecorationStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    if preferences.decorationStyle != .none {
                        Picker("Position", selection: $preferences.decorationPosition) {
                            ForEach(DecorationPosition.allCases) { position in
                                Text(position.label).tag(position)
                            }
                        }
                        sliderRow(decorationSizeLabel, value: $preferences.decorationSize, range: 4...30, step: 1)
                        sliderRow("Opacity", value: $preferences.decorationOpacity, range: 0...1)
                    }
                }

                Section("CRT effect") {
                    Toggle("Scanlines & vignette", isOn: $preferences.crtEnabled)
                    if preferences.crtEnabled {
                        sliderRow("Intensity", value: $preferences.crtIntensity, range: 0...1)
                    }
                    Text("A retro CRT overlay drawn over the panel. Subtle by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Reset to defaults", role: .destructive, action: resetDefaults)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    /// "Ball size" for the boing balls (which the slider scales), "Band size" for
    /// the stripe styles (where it's each band's thickness).
    private var decorationSizeLabel: String {
        preferences.decorationStyle.kind == .ball ? "Ball size" : "Band size"
    }

    // MARK: Preview

    private var preview: some View {
        let model = OverlayModel()
        model.apps = previewApps
        model.selectedIndex = 0
        return OverlayView(model: model, preferences: preferences)
            .scaleEffect(0.7)
    }

    /// One sample per shape class, so the layout controls above show their effect on
    /// all three at once (`UNJAILED.md §8.4`): a free-form silhouette, a rounded
    /// square, and a full-bleed square.
    private var previewApps: [AppInfo] {
        let samples = [("Free-form", "hammer.fill"),
                       ("Rounded", "app.fill"),
                       ("Full-bleed", "square.fill")]
        return samples.enumerated().map { index, sample in
            AppInfo(
                bundleIdentifier: "preview.\(sample.0)",
                name: sample.0,
                processIdentifier: pid_t(index),
                icon: NSImage(systemSymbolName: sample.1, accessibilityDescription: sample.0)
            )
        }
    }

    /// Clear so the preview sits on the same backdrop as the form below it,
    /// avoiding a visible seam where the two areas meet.
    private var previewBackground: some View {
        Color.clear
    }

    // MARK: Rows

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 0.05) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue, range: range)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func format(_ value: Double, range: ClosedRange<Double>) -> String {
        range.upperBound <= 1 ? String(format: "%.0f%%", value * 100) : String(format: "%.0f", value)
    }

    // MARK: Bindings

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<Preferences, String>) -> Binding<Color> {
        Binding(
            get: { Color(hexString: preferences[keyPath: keyPath]) },
            set: { preferences[keyPath: keyPath] = NSColor($0).hexString }
        )
    }

    // MARK: Presets

    /// Writes the current appearance to a user-chosen `.json` file.
    private func exportPreset() {
        let preset = AppearancePreset(name: "Zap Theme", from: preferences)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(preset) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Zap Theme.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            NSLog("Zap: failed to export theme: %@", error.localizedDescription)
        }
    }

    /// Reads a `.json` theme file and applies it (validating every value).
    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let preset = try? JSONDecoder().decode(AppearancePreset.self, from: data) else {
            NSLog("Zap: couldn't read a theme from %@", url.lastPathComponent)
            return
        }
        preset.apply(to: preferences)
    }

    private func resetDefaults() {
        preferences.backgroundColorHex = Preferences.Default.backgroundColorHex
        preferences.useGradientBackground = Preferences.Default.useGradientBackground
        preferences.gradientColorHex = Preferences.Default.gradientColorHex
        preferences.gradientAngle = Preferences.Default.gradientAngle
        preferences.decorationStyle = Preferences.Default.decorationStyle
        preferences.decorationPosition = Preferences.Default.decorationPosition
        preferences.decorationOpacity = Preferences.Default.decorationOpacity
        preferences.decorationSize = Preferences.Default.decorationSize
        preferences.crtEnabled = Preferences.Default.crtEnabled
        preferences.crtIntensity = Preferences.Default.crtIntensity
        preferences.highlightColorHex = Preferences.Default.highlightColorHex
        preferences.labelColorHex = Preferences.Default.labelColorHex
        preferences.backgroundOpacity = Preferences.Default.backgroundOpacity
        preferences.highlightOpacity = Preferences.Default.highlightOpacity
        preferences.iconSize = Preferences.Default.iconSize
        preferences.cornerRadius = Preferences.Default.cornerRadius
        preferences.highlightCornerRadius = Preferences.Default.highlightCornerRadius
        preferences.contentPadding = Preferences.Default.contentPadding
        preferences.showAppName = true
    }
}

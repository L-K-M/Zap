import SwiftUI
import AppKit

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
                        sliderRow("Band size", value: $preferences.decorationSize, range: 4...30, step: 1)
                        sliderRow("Opacity", value: $preferences.decorationOpacity, range: 0...1)
                    }
                }

                Section {
                    Button("Reset to defaults", role: .destructive, action: resetDefaults)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Preview

    private var preview: some View {
        let model = OverlayModel()
        model.apps = previewApps
        model.selectedIndex = 0
        return OverlayView(model: model, preferences: preferences)
            .scaleEffect(0.7)
    }

    private var previewApps: [AppInfo] {
        let names = ["Finder", "Safari", "Mail"]
        return names.enumerated().map { index, name in
            AppInfo(
                bundleIdentifier: "preview.\(name)",
                name: name,
                processIdentifier: pid_t(index),
                icon: NSImage(systemSymbolName: "app.fill", accessibilityDescription: name)
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

    private func resetDefaults() {
        preferences.backgroundColorHex = Preferences.Default.backgroundColorHex
        preferences.useGradientBackground = Preferences.Default.useGradientBackground
        preferences.gradientColorHex = Preferences.Default.gradientColorHex
        preferences.gradientAngle = Preferences.Default.gradientAngle
        preferences.decorationStyle = Preferences.Default.decorationStyle
        preferences.decorationPosition = Preferences.Default.decorationPosition
        preferences.decorationOpacity = Preferences.Default.decorationOpacity
        preferences.decorationSize = Preferences.Default.decorationSize
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

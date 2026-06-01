import SwiftUI

/// General preferences: launch at login, the show delay, and the fallback hotkey.
struct GeneralView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Launch Zap at login", isOn: $preferences.launchAtLogin)
            }

            Section("Timing") {
                VStack(alignment: .leading) {
                    Text("Show delay: \(Int(preferences.showDelayMs)) ms")
                    Slider(value: $preferences.showDelayMs, in: 0...250, step: 10)
                    Text("A short delay lets a quick ⌘-Tab tap switch apps without flashing the switcher.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Trigger") {
                Toggle("Use ⌥-Tab fallback when ⌘-Tab is unavailable", isOn: $preferences.useAlternateHotkey)
                Text("⌘-Tab requires Accessibility permission. Without it, Zap falls back to ⌥-Tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
